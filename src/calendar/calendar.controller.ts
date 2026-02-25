import { Controller, Get, Query, UseGuards, Request } from '@nestjs/common';
import { CalendarService } from './calendar.service';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@Controller('calendar')
export class CalendarController {
  constructor(private readonly calendarService: CalendarService) {}

  /**
   * GET /calendar/summary?month=YYYY-MM
   * Returns { days: [{ dayKey, hasConversation, hasJournalEntry }] }
   */
  @UseGuards(JwtAuthGuard)
  @Get('summary')
  getSummary(@Query('month') month: string, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.calendarService.getMonthSummary(userId, month);
  }
}
