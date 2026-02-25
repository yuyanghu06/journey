import { Injectable } from '@nestjs/common';
import { PrismaService } from '../db/prisma.service';
import { Message } from '@prisma/client';

@Injectable()
export class ChatRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Persist a new message. Returns the created record. */
  async createMessage(data: {
    userId: string | null;
    dayKey: string;
    role: string;
    text: string;
    clientMessageId?: string;
  }): Promise<Message> {
    return this.prisma.message.create({ data });
  }

  /** Fetch all messages for a day, ordered oldest-first. */
  async getByDayKey(userId: string | null, dayKey: string): Promise<Message[]> {
    return this.prisma.message.findMany({
      where: { userId, dayKey },
      orderBy: { timestamp: 'asc' },
    });
  }

  /**
   * Look up an existing message by clientMessageId to support idempotency.
   * Returns the NEXT message (assistant reply) after the matched user message.
   */
  async findAssistantReplyAfterClientId(
    userId: string | null,
    dayKey: string,
    clientMessageId: string,
  ): Promise<Message | null> {
    // Find the user message with this clientMessageId
    const userMsg = await this.prisma.message.findFirst({
      where: { userId, dayKey, clientMessageId, role: 'user' },
      orderBy: { timestamp: 'asc' },
    });
    if (!userMsg) return null;

    // Return the immediately following assistant message
    return this.prisma.message.findFirst({
      where: { userId, dayKey, role: 'assistant', timestamp: { gt: userMsg.timestamp } },
      orderBy: { timestamp: 'asc' },
    });
  }
}
