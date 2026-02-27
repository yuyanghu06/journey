import { Controller, Post, Body, UseGuards, Request } from '@nestjs/common';
import { PersonalityService } from './personality.service';
import { PersonalitySendMessageDto } from './dto/personality-send-message.dto';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@Controller('personality')
export class PersonalityController {
  constructor(private readonly personalityService: PersonalityService) {}

  /**
   * POST /personality/sendMessage
   * Personality-aware chat endpoint. Accepts personalityTokens derived from
   * on-device inference and routes to a dedicated AI call using the personality
   * system prompt. Falls back to the plain chat prompt when tokens array is empty.
   */
  @UseGuards(JwtAuthGuard)
  @Post('sendMessage')
  sendMessage(@Body() dto: PersonalitySendMessageDto, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.personalityService.sendMessage(dto, userId);
  }
}
