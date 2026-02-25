import { Injectable } from '@nestjs/common';
import { ChatRepository } from '../chat/chat.repository';
import { JournalRepository } from '../journal/journal.repository';

@Injectable()
export class DaysService {
  constructor(
    private readonly chatRepo: ChatRepository,
    private readonly journalRepo: JournalRepository,
  ) {}

  /**
   * Returns the full conversation and journal entry for a given day.
   * Maps to GET /days/:dayKey.
   */
  async getDaySnapshot(dayKey: string, userId: string | null) {
    const [messages, journalEntry] = await Promise.all([
      this.chatRepo.getByDayKey(userId, dayKey),
      this.journalRepo.findByDayKey(userId, dayKey),
    ]);

    return {
      conversation: { dayKey, messages },
      journalEntry: journalEntry ?? null,
    };
  }
}
