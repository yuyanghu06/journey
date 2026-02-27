import { Controller, Post, Body, UseGuards, Request } from '@nestjs/common';
import { ChatService } from './chat.service';
import { SendMessageDto } from './dto/send-message.dto';
import { PersonalitySendMessageDto } from './dto/personality-send-message.dto';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@Controller('chat')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  /**
   * POST /chat/sendMessage
   * Requires Bearer token. Extracts userId from JWT payload.
   */
  @UseGuards(JwtAuthGuard)
  @Post('sendMessage')
  sendMessage(@Body() dto: SendMessageDto, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.chatService.sendMessage(dto, userId);
  }

  /**
   * POST /chat/personality
   * Personality-aware chat endpoint. Requires personalityTokens in the request body.
   * Routes to a dedicated AI call using the personality system prompt.
   */
  @UseGuards(JwtAuthGuard)
  @Post('personality')
  sendPersonalityMessage(@Body() dto: PersonalitySendMessageDto, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.chatService.sendPersonalityMessage(dto, userId);
  }
}
