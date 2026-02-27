import { IsArray, IsString, IsOptional, IsNotEmpty, Matches } from 'class-validator';

const DAY_KEY_REGEX = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

export class PersonalitySendMessageDto {
  @IsString()
  @Matches(DAY_KEY_REGEX, { message: 'dayKey must match YYYY-MM-DD' })
  dayKey: string;

  @IsString()
  @IsNotEmpty()
  userText: string;

  @IsString()
  @IsOptional()
  clientMessageId?: string;

  @IsArray()
  @IsString({ each: true })
  personalityTokens: string[];
}
