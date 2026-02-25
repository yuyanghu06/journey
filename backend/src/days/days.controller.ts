import { Controller, Get, Param, UseGuards, Request } from '@nestjs/common';
import { DaysService } from './days.service';
import { DayKeyPipe } from '../common/pipes/daykey.pipe';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@Controller('days')
export class DaysController {
  constructor(private readonly daysService: DaysService) {}

  /**
   * GET /days/:dayKey
   * Returns { conversation: { dayKey, messages[] }, journalEntry: JournalEntry | null }
   */
  @UseGuards(JwtAuthGuard)
  @Get(':dayKey')
  getDaySnapshot(@Param('dayKey', DayKeyPipe) dayKey: string, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.daysService.getDaySnapshot(dayKey, userId);
  }
}
