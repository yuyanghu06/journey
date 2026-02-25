import { Controller, Post, Body, UseGuards, Request } from '@nestjs/common';
import { JournalService } from './journal.service';
import { GenerateJournalDto } from './dto/generate-journal.dto';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@Controller('journal')
export class JournalController {
  constructor(private readonly journalService: JournalService) {}

  /**
   * POST /journal/generate
   * Generates (or regenerates) a journal entry for the given dayKey.
   */
  @UseGuards(JwtAuthGuard)
  @Post('generate')
  generate(@Body() dto: GenerateJournalDto, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.journalService.generate(dto.dayKey, userId);
  }
}
