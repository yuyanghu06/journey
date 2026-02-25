import { Module } from '@nestjs/common';
import { DaysService } from './days.service';
import { DaysController } from './days.controller';
import { ChatModule } from '../chat/chat.module';
import { JournalModule } from '../journal/journal.module';

@Module({
  imports: [ChatModule, JournalModule],
  providers: [DaysService],
  controllers: [DaysController],
})
export class DaysModule {}
