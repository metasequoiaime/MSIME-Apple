//! Reads the safetensors file `tools/sentence-model/export.py` writes.
//!
//! The layout is a little-endian `u64` header length, that many bytes of JSON describing every
//! tensor, then the tensor data. Offsets in the header are relative to the start of the data
//! section. Parsing it here rather than through a library keeps the crate free of dependencies
//! outside the ones the workspace already carries.

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::ModelError;

#[derive(Deserialize)]
struct Entry {
    dtype: String,
    shape: Vec<usize>,
    data_offsets: [usize; 2],
}

/// Every tensor dequantized to `f32`, plus the metadata the header carried.
pub struct Weights {
    tensors: BTreeMap<String, (Vec<usize>, Vec<f32>)>,
    metadata: BTreeMap<String, String>,
}

impl Weights {
    pub fn parse(bytes: &[u8]) -> Result<Self, ModelError> {
        let length_bytes: [u8; 8] = bytes
            .get(..8)
            .ok_or(ModelError::Truncated)?
            .try_into()
            .map_err(|_| ModelError::Truncated)?;
        let header_len = u64::from_le_bytes(length_bytes) as usize;
        let header = bytes.get(8..8 + header_len).ok_or(ModelError::Truncated)?;
        let data = bytes.get(8 + header_len..).ok_or(ModelError::Truncated)?;

        let mut raw: BTreeMap<String, serde_json::Value> = serde_json::from_slice(header)
            .map_err(|error| ModelError::Header(error.to_string()))?;
        let metadata = match raw.remove("__metadata__") {
            Some(value) => serde_json::from_value(value)
                .map_err(|error| ModelError::Header(error.to_string()))?,
            None => BTreeMap::new(),
        };

        // Scales are consumed while dequantizing the tensor they belong to, so they are collected
        // first and never become entries of their own.
        let mut entries: BTreeMap<String, Entry> = BTreeMap::new();
        for (name, value) in raw {
            let entry: Entry = serde_json::from_value(value)
                .map_err(|error| ModelError::Header(format!("{name}: {error}")))?;
            entries.insert(name, entry);
        }

        let mut tensors = BTreeMap::new();
        for (name, entry) in &entries {
            if name.ends_with(".scale") {
                continue;
            }
            let values = match entry.dtype.as_str() {
                "F32" => read_f32(data, entry)?,
                "F16" => read_f16(data, entry)?,
                "I8" => {
                    let scale_entry = entries
                        .get(&format!("{name}.scale"))
                        .ok_or_else(|| ModelError::Header(format!("{name}: missing scale")))?;
                    let scales = read_f32(data, scale_entry)?;
                    read_i8(data, entry, &scales)?
                }
                other => return Err(ModelError::Header(format!("{name}: dtype {other}"))),
            };
            let expected: usize = entry.shape.iter().product();
            if values.len() != expected {
                return Err(ModelError::Header(format!(
                    "{name}: shape does not match data"
                )));
            }
            tensors.insert(name.clone(), (entry.shape.clone(), values));
        }

        Ok(Self { tensors, metadata })
    }

    pub fn take(&mut self, name: &str) -> Result<Vec<f32>, ModelError> {
        self.tensors
            .remove(name)
            .map(|(_, values)| values)
            .ok_or_else(|| ModelError::MissingTensor(name.to_owned()))
    }

    pub fn metadata(&self, key: &str) -> Result<&str, ModelError> {
        self.metadata
            .get(key)
            .map(String::as_str)
            .ok_or_else(|| ModelError::MissingMetadata(key.to_owned()))
    }
}

fn slice<'a>(data: &'a [u8], entry: &Entry) -> Result<&'a [u8], ModelError> {
    data.get(entry.data_offsets[0]..entry.data_offsets[1])
        .ok_or(ModelError::Truncated)
}

fn read_f32(data: &[u8], entry: &Entry) -> Result<Vec<f32>, ModelError> {
    Ok(slice(data, entry)?
        .chunks_exact(4)
        .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .collect())
}

fn read_f16(data: &[u8], entry: &Entry) -> Result<Vec<f32>, ModelError> {
    Ok(slice(data, entry)?
        .chunks_exact(2)
        .map(|b| half_to_f32(u16::from_le_bytes([b[0], b[1]])))
        .collect())
}

/// Quantization is symmetric and per output row, so the scale index is the row index.
fn read_i8(data: &[u8], entry: &Entry, scales: &[f32]) -> Result<Vec<f32>, ModelError> {
    let bytes = slice(data, entry)?;
    let rows = *entry.shape.first().unwrap_or(&1);
    if rows == 0 || scales.len() != rows {
        return Err(ModelError::Header(
            "scale length does not match rows".into(),
        ));
    }
    let columns = bytes.len() / rows;
    Ok(bytes
        .iter()
        .enumerate()
        .map(|(index, &byte)| f32::from(byte as i8) * scales[index / columns])
        .collect())
}

/// IEEE 754 binary16 to binary32. Subnormals are rare in trained weights but are handled rather
/// than flushed, because silently mapping them to zero would be a difference the caller cannot see.
fn half_to_f32(bits: u16) -> f32 {
    let sign = u32::from(bits & 0x8000) << 16;
    let exponent = u32::from((bits >> 10) & 0x1f);
    let mantissa = u32::from(bits & 0x03ff);
    if exponent == 0 {
        if mantissa == 0 {
            return f32::from_bits(sign);
        }
        // Renormalize. A subnormal half is `mantissa * 2^-24`, so its leading set bit sits at
        // `31 - leading_zeros` and the unbiased exponent is that index minus 24.
        let leading = mantissa.leading_zeros();
        let exponent = 134 - leading;
        let mantissa = (mantissa << (leading - 8)) & 0x007f_ffff;
        return f32::from_bits(sign | (exponent << 23) | mantissa);
    }
    if exponent == 0x1f {
        return f32::from_bits(sign | 0x7f80_0000 | (mantissa << 13));
    }
    f32::from_bits(sign | ((exponent + 127 - 15) << 23) | (mantissa << 13))
}

#[cfg(test)]
mod tests {
    use super::half_to_f32;

    #[test]
    fn converts_representative_halves() {
        assert_eq!(half_to_f32(0x0000), 0.0);
        assert_eq!(half_to_f32(0x8000), -0.0);
        assert_eq!(half_to_f32(0x3c00), 1.0);
        assert_eq!(half_to_f32(0xc000), -2.0);
        assert_eq!(half_to_f32(0x3555), 0.333_251_95);
        // Subnormals, which the renormalizing branch has to reach. A subnormal half is exactly
        // `mantissa * 2^-24`, and every such value is representable in f32, so these are exact.
        assert_eq!(half_to_f32(0x03ff), 1023.0 / 16_777_216.0);
        assert_eq!(half_to_f32(0x0001), 1.0 / 16_777_216.0);
        assert_eq!(half_to_f32(0x0200), 512.0 / 16_777_216.0);
        assert_eq!(half_to_f32(0x8001), -1.0 / 16_777_216.0);
        assert!(half_to_f32(0x7c00).is_infinite());
        assert!(half_to_f32(0x7e00).is_nan());
    }
}
