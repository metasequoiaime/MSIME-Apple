//! Reranks candidates the pinyin decoder assembled, using a character-level language model.
//!
//! The model is produced by `tools/sentence-model`, and the measurements that shaped this crate are
//! recorded there. Two of them are load-bearing and are enforced here rather than left to callers:
//!
//! Reranking applies only when the engine's leading candidate was assembled by the lattice or the
//! fallback decoder. An exact dictionary hit on the whole key carries corpus frequency the model
//! does not have, and overriding those costs 14 points of top-1 accuracy at every margin tried.
//!
//! Only candidates covering the whole key are comparable. The engine also returns prefixes, and a
//! summed log-probability is larger for fewer characters, so a mixed-length list would rank the
//! shortest candidate first every time regardless of quality. Scores are per character for the same
//! reason, and the caller restricts the set it passes in.

mod weights;

use std::collections::HashMap;
use std::sync::Arc;

use weights::Weights;

/// `CandidateSource` values meaning an exact full-key hit in a dictionary. The ordering is defined
/// by `quanpin/word_lattice.h` in the engine: `Database` is 0 and `UserDatabase` is 1.
pub const DICTIONARY_SOURCES: [u8; 2] = [0, 1];

/// How many comparable candidates are scored. The engine rarely returns more than a handful that
/// answer the same key — two in almost every real case — so this is a ceiling on the worst case
/// rather than a limit that normally binds.
const COMPARED: usize = 9;

const UNK: u32 = 1;
const BOS: u32 = 2;

#[derive(Debug, thiserror::Error)]
pub enum ModelError {
    #[error("model file is truncated")]
    Truncated,
    #[error("model header: {0}")]
    Header(String),
    #[error("model is missing tensor {0}")]
    MissingTensor(String),
    #[error("model is missing metadata {0}")]
    MissingMetadata(String),
    #[error("model geometry: {0}")]
    Geometry(String),
}

#[derive(Debug, Clone, Copy, serde::Deserialize)]
struct Config {
    vocab: usize,
    n_layer: usize,
    n_head: usize,
    n_embd: usize,
    context: usize,
}

struct Block {
    ln1_weight: Vec<f32>,
    ln1_bias: Vec<f32>,
    qkv_weight: Vec<f32>,
    qkv_bias: Vec<f32>,
    proj_weight: Vec<f32>,
    proj_bias: Vec<f32>,
    ln2_weight: Vec<f32>,
    ln2_bias: Vec<f32>,
    fc_weight: Vec<f32>,
    fc_bias: Vec<f32>,
    out_weight: Vec<f32>,
    out_bias: Vec<f32>,
}

pub struct SentenceModel {
    config: Config,
    index: HashMap<char, u32>,
    token: Vec<f32>,
    position: Vec<f32>,
    blocks: Vec<Block>,
    final_weight: Vec<f32>,
    final_bias: Vec<f32>,
    attribution: String,
}

/// The per-layer keys and values for a prefix, so that scoring several candidates against the same
/// committed text runs the prefix once instead of once per candidate.
struct Prefix {
    length: usize,
    keys: Vec<Vec<f32>>,
    values: Vec<Vec<f32>>,
    /// The normalized hidden state at the last prefix position. Position i predicts token i + 1, so
    /// this is what predicts a candidate's opening character, and without it that character would
    /// go unscored while every later one was counted.
    last_hidden: Vec<f32>,
}

impl SentenceModel {
    pub fn load(bytes: &[u8]) -> Result<Self, ModelError> {
        let mut weights = Weights::parse(bytes)?;
        let config: Config = serde_json::from_str(weights.metadata("config")?)
            .map_err(|error| ModelError::Header(error.to_string()))?;
        let vocabulary: Vec<String> = serde_json::from_str(weights.metadata("vocab")?)
            .map_err(|error| ModelError::Header(error.to_string()))?;
        let attribution = weights
            .metadata("attribution")
            .unwrap_or_default()
            .to_owned();

        if config.n_head == 0 || config.n_embd == 0 || !config.n_embd.is_multiple_of(config.n_head)
        {
            return Err(ModelError::Geometry(format!(
                "{} channels do not divide into {} heads",
                config.n_embd, config.n_head
            )));
        }
        if vocabulary.len() != config.vocab {
            return Err(ModelError::Geometry(format!(
                "vocabulary holds {} tokens but the configuration says {}",
                vocabulary.len(),
                config.vocab
            )));
        }

        let index = vocabulary
            .iter()
            .enumerate()
            .filter_map(|(id, token)| {
                let mut chars = token.chars();
                match (chars.next(), chars.next()) {
                    // Reserved tokens are spelled `<pad>` and are addressed by constant, not by text.
                    (Some(ch), None) => Some((ch, id as u32)),
                    _ => None,
                }
            })
            .collect();

        let mut blocks = Vec::with_capacity(config.n_layer);
        for layer in 0..config.n_layer {
            let name = |suffix: &str| format!("blocks.{layer}.{suffix}");
            blocks.push(Block {
                ln1_weight: weights.take(&name("ln1.weight"))?,
                ln1_bias: weights.take(&name("ln1.bias"))?,
                qkv_weight: weights.take(&name("qkv.weight"))?,
                qkv_bias: weights.take(&name("qkv.bias"))?,
                proj_weight: weights.take(&name("proj.weight"))?,
                proj_bias: weights.take(&name("proj.bias"))?,
                ln2_weight: weights.take(&name("ln2.weight"))?,
                ln2_bias: weights.take(&name("ln2.bias"))?,
                fc_weight: weights.take(&name("fc.weight"))?,
                fc_bias: weights.take(&name("fc.bias"))?,
                out_weight: weights.take(&name("out.weight"))?,
                out_bias: weights.take(&name("out.bias"))?,
            });
        }

        let model = Self {
            config,
            index,
            token: weights.take("tok.weight")?,
            position: weights.take("pos.weight")?,
            blocks,
            final_weight: weights.take("ln_f.weight")?,
            final_bias: weights.take("ln_f.bias")?,
            attribution,
        };
        model.check_geometry()?;
        Ok(model)
    }

    fn check_geometry(&self) -> Result<(), ModelError> {
        let Config {
            vocab,
            n_embd,
            context,
            ..
        } = self.config;
        let expect = |name: &str, actual: usize, wanted: usize| {
            (actual == wanted).then_some(()).ok_or_else(|| {
                ModelError::Geometry(format!("{name} holds {actual}, wanted {wanted}"))
            })
        };
        expect("tok.weight", self.token.len(), vocab * n_embd)?;
        expect("pos.weight", self.position.len(), context * n_embd)?;
        expect("ln_f.weight", self.final_weight.len(), n_embd)?;
        for (layer, block) in self.blocks.iter().enumerate() {
            expect(
                &format!("blocks.{layer}.qkv"),
                block.qkv_weight.len(),
                3 * n_embd * n_embd,
            )?;
            expect(
                &format!("blocks.{layer}.proj"),
                block.proj_weight.len(),
                n_embd * n_embd,
            )?;
            expect(
                &format!("blocks.{layer}.fc"),
                block.fc_weight.len(),
                4 * n_embd * n_embd,
            )?;
            expect(
                &format!("blocks.{layer}.out"),
                block.out_weight.len(),
                4 * n_embd * n_embd,
            )?;
        }
        Ok(())
    }

    /// The corpus attribution carried in the weights file. Both corpora require it to travel with a
    /// model trained on them, which is why it lives in the file rather than beside it.
    pub fn attribution(&self) -> &str {
        &self.attribution
    }

    pub fn context_length(&self) -> usize {
        self.config.context
    }

    fn encode(&self, text: &str) -> Vec<u32> {
        text.chars()
            .map(|ch| self.index.get(&ch).copied().unwrap_or(UNK))
            .collect()
    }

    /// Mean log-probability per character of each candidate, conditioned on the committed text.
    ///
    /// The mean rather than the sum, because candidates of different lengths are otherwise not
    /// comparable. Callers are expected to pass only candidates that cover the whole key, which
    /// makes the lengths equal in practice; normalizing anyway means a caller that gets that wrong
    /// gets a degraded ranking rather than a meaningless one.
    pub fn score(&self, context: &str, candidates: &[&str]) -> Vec<f32> {
        if candidates.is_empty() {
            return Vec::new();
        }
        let longest = candidates
            .iter()
            .map(|text| text.chars().count())
            .max()
            .unwrap_or(0);
        let prefix = self.run_prefix(&self.prefix_tokens(context, longest));
        self.score_against(&prefix, candidates)
    }

    /// The committed text as tokens, opened with `BOS` and trimmed to leave room for the longest
    /// candidate.
    ///
    /// The position table is the hard limit on sequence length, so the context yields rather than
    /// the candidate: a truncated candidate would be scored on text the user did not type, whereas
    /// a truncated context only weakens the conditioning.
    fn prefix_tokens(&self, context: &str, longest: usize) -> Vec<u32> {
        let room = self.config.context.saturating_sub(longest + 1);
        let encoded = self.encode(context);
        let start = encoded.len().saturating_sub(room);
        let mut tokens = Vec::with_capacity(encoded.len() - start + 1);
        tokens.push(BOS);
        tokens.extend_from_slice(&encoded[start..]);
        tokens
    }

    fn score_against(&self, prefix: &Prefix, candidates: &[&str]) -> Vec<f32> {
        candidates
            .iter()
            .map(|text| {
                let tail = self.encode(text);
                if tail.is_empty() {
                    return f32::NEG_INFINITY;
                }
                let limit = self.config.context.saturating_sub(prefix.length).max(1);
                let tail = &tail[..tail.len().min(limit)];
                self.score_tail(prefix, tail) / tail.len() as f32
            })
            .collect()
    }

    fn embed(&self, tokens: &[u32], offset: usize) -> Vec<f32> {
        let n_embd = self.config.n_embd;
        let mut x = vec![0.0; tokens.len() * n_embd];
        for (step, &token) in tokens.iter().enumerate() {
            let token = (token as usize).min(self.config.vocab - 1);
            let position = (offset + step).min(self.config.context - 1);
            let row = &mut x[step * n_embd..(step + 1) * n_embd];
            let token_row = &self.token[token * n_embd..(token + 1) * n_embd];
            let position_row = &self.position[position * n_embd..(position + 1) * n_embd];
            for ((out, &t), &p) in row.iter_mut().zip(token_row).zip(position_row) {
                *out = t + p;
            }
        }
        x
    }

    /// Runs the prefix and keeps every layer's keys and values.
    fn run_prefix(&self, tokens: &[u32]) -> Prefix {
        let n_embd = self.config.n_embd;
        let mut x = self.embed(tokens, 0);
        let mut keys = Vec::with_capacity(self.blocks.len());
        let mut values = Vec::with_capacity(self.blocks.len());
        for block in &self.blocks {
            let normed = layer_norm(&x, &block.ln1_weight, &block.ln1_bias, n_embd);
            let qkv = linear(
                &normed,
                &block.qkv_weight,
                &block.qkv_bias,
                n_embd,
                3 * n_embd,
            );
            let (q, k, v) = split_qkv(&qkv, tokens.len(), n_embd);
            let attended = self.attention(&q, &k, &v, tokens.len(), 0);
            let projected = linear(
                &attended,
                &block.proj_weight,
                &block.proj_bias,
                n_embd,
                n_embd,
            );
            for (slot, value) in x.iter_mut().zip(projected) {
                *slot += value;
            }
            self.feed_forward(&mut x, block);
            keys.push(k);
            values.push(v);
        }
        let last = (tokens.len() - 1) * n_embd;
        let last_hidden = layer_norm(&x[last..], &self.final_weight, &self.final_bias, n_embd);
        Prefix {
            length: tokens.len(),
            keys,
            values,
            last_hidden,
        }
    }

    /// Runs a candidate against a cached prefix and returns its total log-probability.
    fn score_tail(&self, prefix: &Prefix, tail: &[u32]) -> f32 {
        let n_embd = self.config.n_embd;
        let mut x = self.embed(tail, prefix.length);
        for (layer, block) in self.blocks.iter().enumerate() {
            let normed = layer_norm(&x, &block.ln1_weight, &block.ln1_bias, n_embd);
            let qkv = linear(
                &normed,
                &block.qkv_weight,
                &block.qkv_bias,
                n_embd,
                3 * n_embd,
            );
            let (q, k, v) = split_qkv(&qkv, tail.len(), n_embd);
            let mut keys = prefix.keys[layer].clone();
            let mut values = prefix.values[layer].clone();
            keys.extend_from_slice(&k);
            values.extend_from_slice(&v);
            let attended = self.attention(&q, &keys, &values, tail.len(), prefix.length);
            let projected = linear(
                &attended,
                &block.proj_weight,
                &block.proj_bias,
                n_embd,
                n_embd,
            );
            for (slot, value) in x.iter_mut().zip(projected) {
                *slot += value;
            }
            self.feed_forward(&mut x, block);
        }
        let normed = layer_norm(&x, &self.final_weight, &self.final_bias, n_embd);

        // Position i predicts token i + 1. The opening character is therefore predicted by the last
        // prefix position, and every later one by the tail position before it.
        let mut total = self.log_probability(&prefix.last_hidden, tail[0]);
        for step in 0..tail.len() - 1 {
            let hidden = &normed[step * n_embd..(step + 1) * n_embd];
            total += self.log_probability(hidden, tail[step + 1]);
        }
        total
    }

    fn feed_forward(&self, x: &mut [f32], block: &Block) {
        let n_embd = self.config.n_embd;
        let normed = layer_norm(x, &block.ln2_weight, &block.ln2_bias, n_embd);
        let mut hidden = linear(
            &normed,
            &block.fc_weight,
            &block.fc_bias,
            n_embd,
            4 * n_embd,
        );
        for value in &mut hidden {
            *value = gelu(*value);
        }
        let out = linear(
            &hidden,
            &block.out_weight,
            &block.out_bias,
            4 * n_embd,
            n_embd,
        );
        for (slot, value) in x.iter_mut().zip(out) {
            *slot += value;
        }
    }

    /// log P(token) under the tied output projection, computed as the logit minus the log of the
    /// summed exponentials. The full vocabulary is needed for the denominator, which is why this is
    /// the most expensive step per scored character.
    fn log_probability(&self, hidden: &[f32], token: u32) -> f32 {
        let n_embd = self.config.n_embd;
        let mut logits = Vec::with_capacity(self.config.vocab);
        let mut highest = f32::NEG_INFINITY;
        for row in self.token.chunks_exact(n_embd) {
            let logit = dot(hidden, row);
            highest = highest.max(logit);
            logits.push(logit);
        }
        let sum: f32 = logits.iter().map(|logit| (logit - highest).exp()).sum();
        let token = (token as usize).min(self.config.vocab - 1);
        logits[token] - highest - sum.ln()
    }

    fn attention(&self, q: &[f32], k: &[f32], v: &[f32], rows: usize, offset: usize) -> Vec<f32> {
        let n_embd = self.config.n_embd;
        let heads = self.config.n_head;
        let width = n_embd / heads;
        let scale = 1.0 / (width as f32).sqrt();
        let total = k.len() / n_embd;
        let mut out = vec![0.0; rows * n_embd];
        let mut scores = vec![0.0; total];
        for row in 0..rows {
            // Causal: a query at absolute position `offset + row` may attend to itself and earlier.
            let visible = offset + row + 1;
            for head in 0..heads {
                let base = head * width;
                let query = &q[row * n_embd + base..row * n_embd + base + width];
                let mut highest = f32::NEG_INFINITY;
                for (step, score) in scores[..visible].iter_mut().enumerate() {
                    let key = &k[step * n_embd + base..step * n_embd + base + width];
                    *score = dot(query, key) * scale;
                    highest = highest.max(*score);
                }
                let mut sum = 0.0;
                for score in &mut scores[..visible] {
                    *score = (*score - highest).exp();
                    sum += *score;
                }
                let target = &mut out[row * n_embd + base..row * n_embd + base + width];
                for (step, &score) in scores[..visible].iter().enumerate() {
                    let weight = score / sum;
                    let value = &v[step * n_embd + base..step * n_embd + base + width];
                    for (slot, &item) in target.iter_mut().zip(value) {
                        *slot += weight * item;
                    }
                }
            }
        }
        out
    }
}

/// A model plus the prefix it last ran, so that typing does not re-run the committed text.
///
/// The prefix is the expensive half of a short decision — nineteen characters of context cost about
/// as much as the candidates themselves — and it only changes when something is committed, not on
/// every keystroke. Holding it across keystrokes is what puts the decision inside a frame.
pub struct Reranker {
    /// Shared, because the weights are read-only and a host opens a session per focus change.
    /// Only the cached prefix belongs to one session.
    model: Arc<SentenceModel>,
    cached: Option<(Vec<u32>, Prefix)>,
}

impl Reranker {
    pub fn new(model: Arc<SentenceModel>) -> Self {
        Self {
            model,
            cached: None,
        }
    }

    pub fn model(&self) -> &SentenceModel {
        &self.model
    }

    /// The index of the candidate the model prefers over the engine's leader, or `None` to leave the
    /// order alone. Both slices are the engine's candidate list in its own order, and the returned
    /// index refers to that list.
    ///
    /// Selecting the comparable subset happens here rather than in the caller, because which
    /// candidates may be compared is part of the same measured policy as whether to compare at all.
    /// The engine also returns predictive completions that run past the key — `aba` offers 阿巴阿巴
    /// alongside 阿爸 — and those are not alternatives to the leader, they are different lengths of
    /// answer. Candidates matching the leader's length are the ones that answered the same key.
    pub fn best(&mut self, context: &str, texts: &[&str], sources: &[u8]) -> Option<usize> {
        if !should_rerank(sources) {
            return None;
        }
        let width = texts.first()?.chars().count();
        let considered: Vec<usize> = texts
            .iter()
            .enumerate()
            .filter(|(_, text)| text.chars().count() == width)
            .map(|(index, _)| index)
            .take(COMPARED)
            .collect();
        if considered.len() < 2 {
            return None;
        }
        let subset: Vec<&str> = considered.iter().map(|&index| texts[index]).collect();
        let scores = self.score(context, &subset);
        let mut best = 0;
        for (index, score) in scores.iter().enumerate() {
            if *score > scores[best] {
                best = index;
            }
        }
        (best != 0).then(|| considered[best])
    }

    fn score(&mut self, context: &str, candidates: &[&str]) -> Vec<f32> {
        let longest = candidates
            .iter()
            .map(|text| text.chars().count())
            .max()
            .unwrap_or(0);
        // Keyed on the tokens rather than the context string, because two different contexts that
        // truncate to the same window are the same prefix and must not invalidate each other.
        let tokens = self.model.prefix_tokens(context, longest);
        let matched = self
            .cached
            .as_ref()
            .is_some_and(|(cached, _)| *cached == tokens);
        if !matched {
            let prefix = self.model.run_prefix(&tokens);
            self.cached = Some((tokens, prefix));
        }
        let (_, prefix) = self.cached.as_ref().expect("prefix was just computed");
        self.model.score_against(prefix, candidates)
    }
}

/// Whether the model should be consulted at all, given the sources the engine reported in order.
///
/// Only the leading candidate matters. When it is an exact dictionary hit on the whole key it
/// carries corpus frequency the model does not have, and reranking measurably loses accuracy.
pub fn should_rerank(sources: &[u8]) -> bool {
    match sources.first() {
        Some(source) => !DICTIONARY_SOURCES.contains(source),
        None => false,
    }
}

/// Independent accumulators rather than one running sum.
///
/// A single accumulator makes every multiply-add wait for the previous one, so the loop runs at the
/// latency of the fused multiply-add instead of its throughput and leaves most of the core idle.
/// Eight partial sums give the pipeline eight independent chains to interleave. The summation order
/// differs from a serial reduction, which is immaterial here: the result feeds a ranking, and the
/// order was never guaranteed to match the trainer's anyway.
fn dot(a: &[f32], b: &[f32]) -> f32 {
    const LANES: usize = 8;
    let mut partial = [0.0f32; LANES];
    let left = a.chunks_exact(LANES);
    let right = b.chunks_exact(LANES);
    let (tail_left, tail_right) = (left.remainder(), right.remainder());
    for (x, y) in left.zip(right) {
        for lane in 0..LANES {
            partial[lane] += x[lane] * y[lane];
        }
    }
    let mut total = partial.iter().sum::<f32>();
    for (x, y) in tail_left.iter().zip(tail_right) {
        total += x * y;
    }
    total
}

/// `out[m][o] = dot(x[m], w[o]) + bias[o]`, with both operands laid out row-major so every dot
/// product runs over contiguous memory.
fn linear(x: &[f32], w: &[f32], bias: &[f32], inputs: usize, outputs: usize) -> Vec<f32> {
    let rows = x.len() / inputs;
    let mut out = vec![0.0; rows * outputs];
    for row in 0..rows {
        let source = &x[row * inputs..(row + 1) * inputs];
        let target = &mut out[row * outputs..(row + 1) * outputs];
        for (index, slot) in target.iter_mut().enumerate() {
            *slot = dot(source, &w[index * inputs..(index + 1) * inputs]) + bias[index];
        }
    }
    out
}

fn layer_norm(x: &[f32], weight: &[f32], bias: &[f32], width: usize) -> Vec<f32> {
    let mut out = vec![0.0; x.len()];
    for (source, target) in x.chunks_exact(width).zip(out.chunks_exact_mut(width)) {
        let mean = source.iter().sum::<f32>() / width as f32;
        let variance = source
            .iter()
            .map(|value| (value - mean) * (value - mean))
            .sum::<f32>()
            / width as f32;
        let inverse = 1.0 / (variance + 1e-5).sqrt();
        for (index, slot) in target.iter_mut().enumerate() {
            *slot = (source[index] - mean) * inverse * weight[index] + bias[index];
        }
    }
    out
}

fn split_qkv(qkv: &[f32], rows: usize, n_embd: usize) -> (Vec<f32>, Vec<f32>, Vec<f32>) {
    let mut q = vec![0.0; rows * n_embd];
    let mut k = vec![0.0; rows * n_embd];
    let mut v = vec![0.0; rows * n_embd];
    for row in 0..rows {
        let source = &qkv[row * 3 * n_embd..(row + 1) * 3 * n_embd];
        q[row * n_embd..(row + 1) * n_embd].copy_from_slice(&source[..n_embd]);
        k[row * n_embd..(row + 1) * n_embd].copy_from_slice(&source[n_embd..2 * n_embd]);
        v[row * n_embd..(row + 1) * n_embd].copy_from_slice(&source[2 * n_embd..]);
    }
    (q, k, v)
}

/// The exact GELU, matching `torch.nn.functional.gelu` with its default settings. The tanh
/// approximation is a different function and the model was not trained with it.
fn gelu(x: f32) -> f32 {
    0.5 * x * (1.0 + erf(x * std::f32::consts::FRAC_1_SQRT_2))
}

/// Abramowitz and Stegun 7.1.26, whose error stays below 1.5e-7 across the range.
fn erf(x: f32) -> f32 {
    let sign = if x < 0.0 { -1.0 } else { 1.0 };
    let x = x.abs();
    let t = 1.0 / (1.0 + 0.327_591_1 * x);
    let poly = t
        * (0.254_829_6
            + t * (-0.284_496_74 + t * (1.421_413_7 + t * (-1.453_152 + t * 1.061_405_4))));
    sign * (1.0 - poly * (-x * x).exp())
}

#[cfg(test)]
mod tests {
    use super::{erf, gelu, should_rerank};

    #[test]
    fn gate_follows_the_leading_candidate_only() {
        // Database and UserDatabase lead: the dictionary knows the whole key, leave it alone.
        assert!(!should_rerank(&[0, 8, 9]));
        assert!(!should_rerank(&[1, 8]));
        // Lattice or fallback leads: no frequency evidence, so the model is worth consulting.
        assert!(should_rerank(&[8, 0, 0]));
        assert!(should_rerank(&[9, 0]));
        // Nothing to reorder.
        assert!(!should_rerank(&[]));
    }

    #[test]
    fn erf_matches_known_values() {
        assert!((erf(0.0) - 0.0).abs() < 1e-6);
        assert!((erf(0.5) - 0.520_499_9).abs() < 1e-6);
        assert!((erf(1.0) - 0.842_700_8).abs() < 1e-6);
        assert!((erf(-1.0) + 0.842_700_8).abs() < 1e-6);
        assert!((erf(3.0) - 0.999_977_9).abs() < 1e-6);
    }

    #[test]
    fn gelu_matches_torch_reference() {
        // Values taken from torch.nn.functional.gelu with its default exact formulation.
        assert!((gelu(0.0) - 0.0).abs() < 1e-6);
        assert!((gelu(1.0) - 0.841_344_8).abs() < 1e-6);
        assert!((gelu(-1.0) + 0.158_655_25).abs() < 1e-6);
        assert!((gelu(2.0) - 1.954_499_7).abs() < 1e-6);
    }
}
