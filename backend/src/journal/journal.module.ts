import { Module } from '@nestjs/common';
import { JournalService } from './journal.service';
import { JournalController } from './journal.controller';
import { JournalRepository } from './journal.repository';
import { AiModule } from '../ai/ai.module';
import { ChatModule } from '../chat/chat.module';

@Module({
  imports: [AiModule, ChatModule],
  providers: [JournalService, JournalRepository],
  controllers: [JournalController],
  exports: [JournalRepository],
})
export class JournalModule {}
