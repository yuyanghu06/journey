import { Controller, Get, Post, Param, Body, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

/**
 * Stub endpoints for legacy iOS AuthService calls.
 * These keep the client from crashing while the new API is wired up.
 * Full implementation is post-MVP.
 */
@Controller()
@UseGuards(JwtAuthGuard)
export class LegacyController {
  /** GET /history/:date — returns empty compressed history */
  @Get('history/:date')
  getHistory(@Param('date') date: string) {
    return { compressed_history: '' };
  }

  /** POST /history — accepts and discards legacy history payload */
  @Post('history')
  postHistory(@Body() _body: any) {
    return { ok: true };
  }

  /** GET /summaries/:date — returns empty summaries list */
  @Get('summaries/:date')
  getSummaries(@Param('date') date: string) {
    return { summaries: [] };
  }
}
