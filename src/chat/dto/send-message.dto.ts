import { IsString, IsOptional, Matches } from 'class-validator';

const DAY_KEY_REGEX = /^\d{4}-\d{2}-\d{2}$/;

export class SendMessageDto {
  @IsString()
  @Matches(DAY_KEY_REGEX, { message: 'dayKey must match YYYY-MM-DD' })
  dayKey: string;

  @IsString()
  userText: string;

  @IsString()
  @IsOptional()
  clientMessageId?: string;
}
