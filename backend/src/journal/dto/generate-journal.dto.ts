import { IsString, Matches } from 'class-validator';

const DAY_KEY_REGEX = /^\d{4}-\d{2}-\d{2}$/;

export class GenerateJournalDto {
  @IsString()
  @Matches(DAY_KEY_REGEX, { message: 'dayKey must match YYYY-MM-DD' })
  dayKey: string;
}
