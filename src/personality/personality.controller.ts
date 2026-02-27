import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { PersonalityService } from './personality.service';
import { PersonalitySendMessageDto } from './dto/personality-send-message.dto';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@Controller('personality')
export class PersonalityController {
  constructor(private readonly personalityService: PersonalityService) {}

  /**
   * POST /personality/sendMessage
   * Stateless personality-aware chat.
   * Accepts the full conversation history and memories from the client.
   * Nothing is persisted — personality conversations are stored locally on-device.
   */
  @UseGuards(JwtAuthGuard)
  @Post('sendMessage')
  sendMessage(@Body() dto: PersonalitySendMessageDto) {
    return this.personalityService.sendMessage(dto);
  }
}
