import { Injectable, BadRequestException } from '@nestjs/common';
import { PrismaService } from '../db/prisma.service';

const MONTH_REGEX = /^\d{4}-(0[1-9]|1[0-2])$/;

export interface DaySummary {
  dayKey: string;
  hasConversation: boolean;
  hasJournalEntry: boolean;
}

@Injectable()
export class CalendarService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Returns activity indicators for every day in the given YYYY-MM month.
   * Uses two aggregation queries instead of N+1 per day.
   */
  async getMonthSummary(
    userId: string | null,
    month: string,
  ): Promise<{ days: DaySummary[] }> {
    if (!MONTH_REGEX.test(month)) {
      throw new BadRequestException('month must match YYYY-MM');
    }

    const [year, mo] = month.split('-').map(Number);
    const firstDay = `${month}-01`;
    const lastDay  = this.lastDayOfMonth(year, mo);

    // Fetch distinct dayKeys for messages and journal entries in range
    const [msgDays, journalDays] = await Promise.all([
      this.prisma.message.findMany({
        where: { userId, dayKey: { gte: firstDay, lte: lastDay } },
        select: { dayKey: true },
        distinct: ['dayKey'],
      }),
      this.prisma.journalEntry.findMany({
        where: { userId, dayKey: { gte: firstDay, lte: lastDay } },
        select: { dayKey: true },
      }),
    ]);

    const conversationSet = new Set(msgDays.map((r) => r.dayKey));
    const journalSet      = new Set(journalDays.map((r) => r.dayKey));

    // Build a full set of all active days
    const allKeys = new Set([...conversationSet, ...journalSet]);
    const days: DaySummary[] = Array.from(allKeys)
      .sort()
      .map((dayKey) => ({
        dayKey,
        hasConversation: conversationSet.has(dayKey),
        hasJournalEntry: journalSet.has(dayKey),
      }));

    return { days };
  }

  private lastDayOfMonth(year: number, month: number): string {
    const d = new Date(year, month, 0); // day 0 = last day of previous month
    return `${year}-${String(month).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
}
