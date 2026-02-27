import { Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { AiService, AiMessage } from '../ai/ai.service';
import { PersonalitySendMessageDto } from './dto/personality-send-message.dto';

export interface PersonalityAssistantMessage {
  id: string;
  dayKey: string;
  role: 'assistant';
  text: string;
  timestamp: string;
}

@Injectable()
export class PersonalityService {
  private readonly logger = new Logger(PersonalityService.name);

  constructor(private readonly ai: AiService) {}

  /**
   * Stateless personality chat.
   * Uses the client-provided conversation history and memories as context.
   * Nothing is persisted to the database — personality conversations live locally on-device.
   */
  async sendMessage(
    dto: PersonalitySendMessageDto,
  ): Promise<{ assistantMessage: PersonalityAssistantMessage }> {
    const { dayKey, userText, personalityTokens, conversationHistory = [], memories = [] } = dto;

    // Build AI context from the client-supplied history + the new user message
    const aiMessages: AiMessage[] = [
      ...conversationHistory.map((m) => ({
        role: m.role as 'user' | 'assistant' | 'system',
        content: m.text,
      })),
      { role: 'user', content: userText },
    ];

    const replyText = await this.ai.chatWithPersonality(
      aiMessages,
      personalityTokens,
      memories,
    );

    this.logger.log(
      `personality reply generated (tokens: ${personalityTokens.length}, history: ${conversationHistory.length} msgs)`,
    );

    return {
      assistantMessage: {
        id: randomUUID(),
        dayKey,
        role: 'assistant',
        text: replyText,
        timestamp: new Date().toISOString(),
      },
    };
  }
}
