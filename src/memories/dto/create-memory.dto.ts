import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

export class CreateMemoryDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  title: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(50_000)
  text: string;
}
