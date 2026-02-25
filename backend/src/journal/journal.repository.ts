import { Injectable } from '@nestjs/common';
import { PrismaService } from '../db/prisma.service';
import { JournalEntry } from '@prisma/client';

@Injectable()
export class JournalRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** Returns the journal entry for the given user+day, or null if none exists. */
  async findByDayKey(userId: string | null, dayKey: string): Promise<JournalEntry | null> {
    return this.prisma.journalEntry.findFirst({ where: { userId, dayKey } });
  }

  /**
   * Creates or updates the journal entry for the given user+day.
   * Uses update-or-create pattern because Prisma's upsert requires a
   * unique-constraint value that can't be null.
   */
  async upsert(userId: string | null, dayKey: string, text: string): Promise<JournalEntry> {
    const existing = await this.findByDayKey(userId, dayKey);
    if (existing) {
      return this.prisma.journalEntry.update({
        where: { id: existing.id },
        data: { text },
      });
    }
    return this.prisma.journalEntry.create({
      data: { userId, dayKey, text },
    });
  }

  /** Returns all dayKeys that have journal entries for the given user. */
  async listDayKeys(userId: string | null): Promise<string[]> {
    const entries = await this.prisma.journalEntry.findMany({
      where: { userId },
      select: { dayKey: true },
    });
    return entries.map((e) => e.dayKey);
  }
}
