import { Injectable, Logger } from '@nestjs/common';
import { AiService, AiMessage } from '../ai/ai.service';
import { ChatRepository } from '../chat/chat.repository';
import { PersonalitySendMessageDto } from './dto/personality-send-message.dto';
import { Message } from '@prisma/client';

@Injectable()
export class PersonalityService {
  private readonly logger = new Logger(PersonalityService.name);

  constructor(
    private readonly repo: ChatRepository,
    private readonly ai: AiService,
  ) {}

  async sendMessage(
    dto: PersonalitySendMessageDto,
    userId: string | null,
  ): Promise<{ assistantMessage: Message }> {
    const { dayKey, userText, clientMessageId, personalityTokens } = dto;

    // --- Idempotency check ---
    if (clientMessageId) {
      const cached = await this.repo.findAssistantReplyAfterClientId(
        userId,
        dayKey,
        clientMessageId,
      );
      if (cached) {
        this.logger.log(`Idempotent hit for clientMessageId ${clientMessageId}`);
        return { assistantMessage: cached };
      }
    }

    // --- 1. Persist the user message FIRST (never lose it) ---
    await this.repo.createMessage({
      userId,
      dayKey,
      role: 'user',
      text: userText,
      clientMessageId,
    });

    // --- 2. Load prior conversation for context ---
    const priorMessages = await this.repo.getByDayKey(userId, dayKey);

    // --- 3. Build context window for the AI ---
    const aiMessages: AiMessage[] = priorMessages.map((m) => ({
      role: m.role as 'user' | 'assistant' | 'system',
      content: m.text,
    }));

    // --- 4. Call AI with personality tokens (falls back to plain chat if tokens empty) ---
    const replyText =
      personalityTokens.length > 0
        ? await this.ai.chatWithPersonality(aiMessages, personalityTokens)
        : await this.ai.chat(aiMessages);

    // --- 5. Persist and return assistant reply ---
    const assistantMessage = await this.repo.createMessage({
      userId,
      dayKey,
      role: 'assistant',
      text: replyText,
    });

    return { assistantMessage };
  }
}
