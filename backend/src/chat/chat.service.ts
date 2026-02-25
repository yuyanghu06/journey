import { Injectable, Logger } from '@nestjs/common';
import { AiService, AiMessage } from '../ai/ai.service';
import { ChatRepository } from './chat.repository';
import { SendMessageDto } from './dto/send-message.dto';
import { Message } from '@prisma/client';

@Injectable()
export class ChatService {
  private readonly logger = new Logger(ChatService.name);

  constructor(
    private readonly repo: ChatRepository,
    private readonly ai: AiService,
  ) {}

  async sendMessage(
    dto: SendMessageDto,
    userId: string | null,
  ): Promise<{ assistantMessage: Message }> {
    const { dayKey, userText, clientMessageId } = dto;

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

    // --- 4. Call AI (may throw — user message is already safe) ---
    const replyText = await this.ai.chat(aiMessages);

    // --- 5. Persist assistant reply ---
    const assistantMessage = await this.repo.createMessage({
      userId,
      dayKey,
      role: 'assistant',
      text: replyText,
    });

    return { assistantMessage };
  }
}
