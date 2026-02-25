import { Controller, Post, Body, UseGuards, Request } from '@nestjs/common';
import { ChatService } from './chat.service';
import { SendMessageDto } from './dto/send-message.dto';
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
}
