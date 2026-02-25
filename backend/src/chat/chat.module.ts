import { Module } from '@nestjs/common';
import { ChatService } from './chat.service';
import { ChatController } from './chat.controller';
import { ChatRepository } from './chat.repository';
import { AiModule } from '../ai/ai.module';

@Module({
  imports: [AiModule],
  providers: [ChatService, ChatRepository],
  controllers: [ChatController],
  exports: [ChatRepository],
})
export class ChatModule {}
