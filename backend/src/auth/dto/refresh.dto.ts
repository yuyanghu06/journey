import { IsString, IsOptional } from 'class-validator';

export class RefreshDto {
  @IsString()
  @IsOptional()
  userId?: string;

  @IsString()
  refreshToken: string;
}
