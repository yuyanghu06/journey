import { Module } from '@nestjs/common';
import { PersonalityService } from './personality.service';
import { PersonalityController } from './personality.controller';
import { AiModule } from '../ai/ai.module';
import { ChatModule } from '../chat/chat.module';

@Module({
  imports: [AiModule, ChatModule],
  providers: [PersonalityService],
  controllers: [PersonalityController],
})
export class PersonalityModule {}
