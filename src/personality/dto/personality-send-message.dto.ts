import {
  IsArray,
  IsString,
  IsOptional,
  IsNotEmpty,
  Matches,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

const DAY_KEY_REGEX = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

export class HistoryMessageDto {
  @IsString()
  dayKey: string;

  @IsString()
  role: string;

  @IsString()
  text: string;
}

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

  /** Full conversation history from the client — used as AI context, NOT persisted. */
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => HistoryMessageDto)
  @IsOptional()
  conversationHistory?: HistoryMessageDto[];

  /** Raw text from the user's saved memory/context documents. */
  @IsArray()
  @IsString({ each: true })
  @IsOptional()
  memories?: string[];
}
