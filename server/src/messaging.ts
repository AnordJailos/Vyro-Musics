/** How codes reach people. A real email and SMS provider plugs in here. */
export interface Messenger {
  email(to: string, subject: string, body: string): Promise<void>;
  sms(to: string, body: string): Promise<void>;
}

/** Development only: prints messages to the server console. */
export class ConsoleMessenger implements Messenger {
  async email(to: string, subject: string, body: string) {
    console.log(`[email to ${to}] ${subject}\n${body}`);
  }
  async sms(to: string, body: string) {
    console.log(`[sms to ${to}] ${body}`);
  }
}

/** Tests: keeps every message so the code can be read back. */
export class MemoryMessenger implements Messenger {
  sent: { channel: 'email' | 'sms'; to: string; subject: string; body: string }[] = [];

  async email(to: string, subject: string, body: string) {
    this.sent.push({ channel: 'email', to, subject, body });
  }
  async sms(to: string, body: string) {
    this.sent.push({ channel: 'sms', to, subject: '', body });
  }

  /** The six-digit code in the latest message to this address or number. */
  lastCode(to: string): string {
    const msg = [...this.sent].reverse().find((m) => m.to === to);
    const code = msg?.body.match(/\b(\d{6})\b/)?.[1];
    if (!code) throw new Error(`no code was sent to ${to}`);
    return code;
  }
}

export const codeText = (what: string, code: string) =>
  `Your Vyro code ${what} is ${code}. It works for 10 minutes. If you did not ask for it, you can ignore this message.`;
