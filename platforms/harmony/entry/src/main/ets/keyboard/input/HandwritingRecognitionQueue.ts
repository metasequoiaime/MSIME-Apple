export interface HandwritingRecognitionTicket {
  readonly revision: number;
}

/** Serialises platform OCR while retaining only the newest changed canvas. */
export class HandwritingRecognitionQueue {
  private revision: number = 0;
  private running: boolean = false;
  private pending: boolean = false;

  changed(): void {
    this.revision++;
    this.pending = false;
  }

  request(): HandwritingRecognitionTicket | null {
    if (this.running) {
      this.pending = true;
      return null;
    }
    this.running = true;
    this.pending = false;
    return { revision: this.revision };
  }

  accepts(ticket: HandwritingRecognitionTicket): boolean {
    return ticket.revision === this.revision;
  }

  finish(): HandwritingRecognitionTicket | null {
    this.running = false;
    if (!this.pending) {
      return null;
    }
    this.pending = false;
    this.running = true;
    return { revision: this.revision };
  }
}
