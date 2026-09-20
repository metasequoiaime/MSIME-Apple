/**
 * The sequencing of one AI skin generation, kept apart from the requests it sequences.
 *
 * The run is four kinds of request — the model catalog, one chat, and then three artwork jobs that
 * are each a create, a poll and a release — and what makes it worth its own file is not the
 * requests but the rules between them. Cancellation has to be honoured between every step and not
 * merely at the start; a failed job has to stop the other two rather than let them keep billing; a
 * job has to be released whether it succeeded, failed or was abandoned; and progress is counted in
 * finished pictures, because that is the only number that means anything to someone watching.
 *
 * None of that needs a network to be tested, and all of it is the part that goes wrong. The
 * transport is injected, so these rules can be exercised against scripted answers.
 */

/** One artwork job, as the service describes it. */
export type ArtworkJob = { id: string; state: string; artwork?: Object };

export type AiSkinPlan = {
  name: string;
  description: string;
  artworkPrompt: string;
  design: Object;
};

export type AiSkinProposal = AiSkinPlan & { artwork: Object };

/**
 * Everything the run needs from outside itself.
 *
 * `validateArtwork` is a call into the shared client rather than a check written here: whether a
 * returned image is usable is the same question on every host, and this one has no business
 * answering it.
 */
export interface AiSkinRunner {
  defaultModel(): Promise<string>;
  chat(prompt: string, model: string): Promise<string>;
  plans(text: string): AiSkinPlan[];
  createJob(artworkPrompt: string): Promise<ArtworkJob>;
  readJob(id: string): Promise<ArtworkJob>;
  deleteJob(id: string): Promise<void>;
  validateArtwork(artwork: Object): boolean;
  /** Resolves after the given delay, so a poll can be paced without a real clock in tests. */
  wait(milliseconds: number): Promise<void>;
  now(): number;
}

export class AiSkinCancelled extends Error {
  constructor() {
    super("ai_skin_cancelled");
    this.name = "AiSkinCancelled";
  }
}

export class AiSkinFailure extends Error {
  constructor(code: string) {
    super(code);
    this.name = "AiSkinFailure";
  }
}

/** The shared service waits this long for one picture before giving up on it. */
const MAX_ARTWORK_MS = 200 * 1000;
const POLL_INTERVAL_MS = 5 * 1000;

/** Mirrors the shared service: 48 lowercase hex characters, checked before it enters a path. */
function validJobId(value: string): boolean {
  return typeof value === "string" && /^[0-9a-f]{48}$/.test(value);
}

export class AiSkinRun {
  private readonly runner: AiSkinRunner;
  private cancelledFlag = false;

  constructor(runner: AiSkinRunner) {
    this.runner = runner;
  }

  cancel(): void {
    this.cancelledFlag = true;
  }

  get cancelled(): boolean {
    return this.cancelledFlag;
  }

  private checkCancelled(): void {
    if (this.cancelledFlag) throw new AiSkinCancelled();
  }

  /**
   * One generation, from a description to three illustrated designs.
   *
   * `progress` is called with the number of finished pictures rather than a fraction of the whole
   * run: the catalog and the chat are quick and the three pictures are not, so a percentage that
   * spent most of its life at the same value would say less than "1 / 3".
   */
  async generate(prompt: string, progress: (completed: number) => void): Promise<AiSkinProposal[]> {
    this.checkCancelled();
    const model = await this.runner.defaultModel();
    this.checkCancelled();
    const answer = await this.runner.chat(prompt, model);
    this.checkCancelled();
    const plans = this.runner.plans(answer);
    if (plans.length !== 3) throw new AiSkinFailure("ai_skin_response");
    this.checkCancelled();

    let completed = 0;
    // Started together rather than in turn: three pictures in sequence is three times the wait,
    // and the service issues them independently.
    const results = await Promise.allSettled(
      plans.map(async (plan) => {
        const artwork = await this.illustrate(plan.artworkPrompt);
        completed += 1;
        progress(completed);
        return { ...plan, artwork } as AiSkinProposal;
      }),
    );
    const failure = results.find((result) => result.status === "rejected");
    if (failure !== undefined) {
      // The first failure ends the other two. Leaving them running would keep spending on pictures
      // for a set the user is never going to be shown.
      this.cancelledFlag = true;
      const reason = (failure as PromiseRejectedResult).reason;
      throw reason instanceof Error ? reason : new AiSkinFailure("ai_skin_unavailable");
    }
    return results.map((result) => (result as PromiseFulfilledResult<AiSkinProposal>).value);
  }

  /**
   * One picture: create the job, wait for it, and release it whichever way it ends.
   *
   * The release is in a finally rather than on the success path. A cancelled or failed run must not
   * leave an upstream task alive — it is the user's account it is being charged to, and nothing
   * left on this device would ever go back to stop it.
   */
  private async illustrate(artworkPrompt: string): Promise<Object> {
    this.checkCancelled();
    const job = await this.runner.createJob(artworkPrompt);
    if (!validJobId(job.id)) throw new AiSkinFailure("ai_skin_response");
    try {
      return await this.poll(job);
    } finally {
      try {
        await this.runner.deleteJob(job.id);
      } catch {
        // A job that cannot be released is reported by nothing here: the run's own outcome is what
        // the user is waiting on, and replacing it with a cleanup failure would hide it.
      }
    }
  }

  private async poll(initial: ArtworkJob): Promise<Object> {
    const deadline = this.runner.now() + MAX_ARTWORK_MS;
    let job = initial;
    for (;;) {
      this.checkCancelled();
      if (job.state === "succeeded") {
        if (job.artwork === undefined || !this.runner.validateArtwork(job.artwork)) {
          throw new AiSkinFailure("ai_skin_response");
        }
        return job.artwork;
      }
      if (job.state !== "running") throw new AiSkinFailure("ai_skin_unavailable");
      if (this.runner.now() >= deadline) throw new AiSkinFailure("ai_skin_unavailable");
      await this.runner.wait(POLL_INTERVAL_MS);
      this.checkCancelled();
      job = await this.runner.readJob(initial.id);
      if (job.id !== initial.id) throw new AiSkinFailure("ai_skin_response");
    }
  }
}
