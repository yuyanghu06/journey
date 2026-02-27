import { IsArray, IsString, ArrayNotEmpty } from 'class-validator';
import { SendMessageDto } from './send-message.dto';

export class PersonalitySendMessageDto extends SendMessageDto {
  @IsArray()
  @ArrayNotEmpty()
  @IsString({ each: true })
  personalityTokens: string[];
}
