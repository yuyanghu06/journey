import { Injectable, Logger } from '@nestjs/common';
import { AiService } from '../ai/ai.service';
import { JournalRepository } from './journal.repository';
import { ChatRepository } from '../chat/chat.repository';
import { JournalEntry } from '@prisma/client';

@Injectable()
export class JournalService {
  private readonly logger = new Logger(JournalService.name);

  constructor(
    private readonly journalRepo: JournalRepository,
    private readonly chatRepo: ChatRepository,
    private readonly ai: AiService,
  ) {}

  async generate(
    dayKey: string,
    userId: string | null,
  ): Promise<{ journalEntry: JournalEntry }> {
    // Fetch the day's conversation
    const messages = await this.chatRepo.getByDayKey(userId, dayKey);

    // Build a plain-text summary of the conversation for the AI
    const conversationText = messages
      .filter((m) => m.role !== 'system')
      .map((m) => `${m.role === 'user' ? 'Me' : 'Journey'}: ${m.text}`)
      .join('\n');

    // Call AI — JournalService is the only other permitted caller of AiService
    const text = await this.ai.summarise(conversationText);

    // Upsert — replaces any existing entry for this user+day
    const journalEntry = await this.journalRepo.upsert(userId, dayKey, text);
    this.logger.log(`Journal entry upserted for ${dayKey} (userId: ${userId})`);

    return { journalEntry };
  }
}
