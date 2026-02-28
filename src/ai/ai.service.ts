import { Injectable, ServiceUnavailableException, Logger } from '@nestjs/common';
import * as fs from 'fs';
import * as path from 'path';
import OpenAI from 'openai';

export interface AiMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

// Maximum characters to feed into the context window before truncation
const MAX_CONTEXT_CHARS = 24_000;

function loadPrompt(filename: string): string {
  const filePath = path.join(process.cwd(), 'prompts', filename);
  return fs.readFileSync(filePath, 'utf-8').trim();
}

@Injectable()
export class AiService {
  private readonly client: OpenAI;
  private readonly logger = new Logger(AiService.name);
  private readonly chatSystemPrompt: string;
  private readonly journalSystemPrompt: string;
  private readonly personalitySystemPromptTemplate: string;

  constructor() {
    this.client = new OpenAI({ apiKey: process.env.AI_PROVIDER_KEY });
    this.chatSystemPrompt = loadPrompt('chat.txt');
    this.journalSystemPrompt = loadPrompt('journal.txt');
    this.personalitySystemPromptTemplate = loadPrompt('personality.txt');
  }

  /**
   * Sends a conversation to the AI and returns the assistant's reply text.
   * Called ONLY from ChatService — never from controllers or other services.
   */
  async chat(messages: AiMessage[]): Promise<string> {
    const trimmed = this.truncateMessages(messages);
    const payload: AiMessage[] = [
      { role: 'system', content: this.chatSystemPrompt },
      ...trimmed,
    ];

    return this.callWithRetry(payload, 'chat');
  }

  /**
   * Sends a conversation to the AI using a personality-aware system prompt.
   * personalityTokens are injected into the prompt to tailor the AI's voice.
   * memories (optional) are personal context notes injected as background.
   * Called ONLY from PersonalityService — never from controllers or other services.
   */
  async chatWithPersonality(
    messages: AiMessage[],
    personalityTokens: string[],
    memories: string[] = [],
  ): Promise<string> {
    const tokenList = personalityTokens.join(', ');
    const memoriesSection =
      memories.length > 0
        ? `Personal context and memories:\n${memories.map((m) => `- ${m}`).join('\n')}`
        : '';
    const systemPrompt = this.personalitySystemPromptTemplate
      .replace('{PERSONALITY_TOKENS}', tokenList || 'none')
      .replace('{MEMORIES_SECTION}', memoriesSection);
    const trimmed = this.truncateMessages(messages);
    const payload: AiMessage[] = [
      { role: 'system', content: systemPrompt },
      ...trimmed,
    ];

    return this.callWithRetry(payload, 'chatWithPersonality');
  }

  /**
   * Generates a reflective journal entry from a list of conversation messages.
   * Called ONLY from JournalService.
   */
  async summarise(conversationText: string): Promise<string> {
    const payload: AiMessage[] = [
      { role: 'system', content: this.journalSystemPrompt },
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
    this.logger.log(
      `[${context}] INPUT (attempt ${attempt}):\n${JSON.stringify(messages, null, 2)}`,
    );
    try {
      const completion = await this.client.chat.completions.create({
        model: 'gpt-4o-mini',
        messages,
        max_tokens: 512,
        temperature: 0.7,
      });

      const output = completion.choices[0]?.message?.content?.trim() ?? '';
      this.logger.log(`[${context}] OUTPUT:\n${output}`);
      return output;
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
