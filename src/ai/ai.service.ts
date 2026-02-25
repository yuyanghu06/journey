import { Injectable, ServiceUnavailableException, Logger } from '@nestjs/common';
import OpenAI from 'openai';

export interface AiMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

// Maximum characters to feed into the context window before truncation
const MAX_CONTEXT_CHARS = 24_000;

const CHAT_SYSTEM_PROMPT = `You are Journey — a calm, reflective AI companion. Your role is to help the user \
process their thoughts and feelings through gentle, open-ended conversation. \
Be warm, brief, and curious. Never give advice unless asked. Never judge. \
Always respond in 1–3 short sentences.`;

const JOURNAL_SYSTEM_PROMPT = `You are a thoughtful journaling assistant. \
Write a single reflective journal entry in first person (2–4 sentences) \
that captures the emotional essence of the conversation below. \
Use a calm, personal tone. Do not invent events not mentioned.`;

@Injectable()
export class AiService {
  private readonly client: OpenAI;
  private readonly logger = new Logger(AiService.name);

  constructor() {
    this.client = new OpenAI({ apiKey: process.env.AI_PROVIDER_KEY });
  }

  /**
   * Sends a conversation to the AI and returns the assistant's reply text.
   * Called ONLY from ChatService — never from controllers or other services.
   */
  async chat(messages: AiMessage[]): Promise<string> {
    const trimmed = this.truncateMessages(messages);
    const payload: AiMessage[] = [
      { role: 'system', content: CHAT_SYSTEM_PROMPT },
      ...trimmed,
    ];

    return this.callWithRetry(payload, 'chat');
  }

  /**
   * Generates a reflective journal entry from a list of conversation messages.
   * Called ONLY from JournalService.
   */
  async summarise(conversationText: string): Promise<string> {
    const payload: AiMessage[] = [
      { role: 'system', content: JOURNAL_SYSTEM_PROMPT },
      { role: 'user', content: `Conversation:\n${conversationText}` },
    ];

    return this.callWithRetry(payload, 'summarise');
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private async callWithRetry(
    messages: AiMessage[],
    context: string,
    attempt = 1,
  ): Promise<string> {
    try {
      const completion = await this.client.chat.completions.create({
        model: 'gpt-4o-mini',
        messages,
        max_tokens: 512,
        temperature: 0.7,
      });

      return completion.choices[0]?.message?.content?.trim() ?? '';
    } catch (err: any) {
      const status = err?.status ?? 0;

      // Retry once on rate-limit (429) or server error (5xx)
      if (attempt === 1 && (status === 429 || status >= 500)) {
        const delay = status === 429 ? 2000 : 1000;
        this.logger.warn(`AI ${context} failed (${status}), retrying in ${delay}ms`);
        await new Promise((r) => setTimeout(r, delay));
        return this.callWithRetry(messages, context, 2);
      }

      this.logger.error(`AI ${context} failed after ${attempt} attempt(s): ${err?.message}`);
      throw new ServiceUnavailableException('AI service temporarily unavailable');
    }
  }

  /** Trim oldest messages to stay within the character budget. */
  private truncateMessages(messages: AiMessage[]): AiMessage[] {
    let total = 0;
    const result: AiMessage[] = [];

    // Walk from newest to oldest to keep the most recent context
    for (let i = messages.length - 1; i >= 0; i--) {
      total += messages[i].content.length;
      if (total > MAX_CONTEXT_CHARS) break;
      result.unshift(messages[i]);
    }

    return result;
  }
}
