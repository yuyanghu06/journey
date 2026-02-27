import { Module } from '@nestjs/common';
import { DbModule } from './db/db.module';
import { AiModule } from './ai/ai.module';
import { AuthModule } from './auth/auth.module';
import { ChatModule } from './chat/chat.module';
import { JournalModule } from './journal/journal.module';
import { CalendarModule } from './calendar/calendar.module';
import { DaysModule } from './days/days.module';
import { HealthModule } from './health/health.module';
import { LegacyModule } from './legacy/legacy.module';
import { PersonalityModule } from './personality/personality.module';

@Module({
  imports: [
    DbModule,
    AiModule,
    AuthModule,
    ChatModule,
    JournalModule,
    CalendarModule,
    DaysModule,
    HealthModule,
    LegacyModule,
    PersonalityModule,
  ],
})
export class AppModule {}
