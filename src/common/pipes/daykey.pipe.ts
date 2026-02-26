import { PipeTransform, Injectable, BadRequestException } from '@nestjs/common';

const DAY_KEY_REGEX = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

/**
 * Validates that a string parameter is a valid YYYY-MM-DD DayKey.
 * Apply with @Param('dayKey', DayKeyPipe) or in DTO validation.
 */
@Injectable()
export class DayKeyPipe implements PipeTransform<string, string> {
  transform(value: string): string {
    if (!DAY_KEY_REGEX.test(value)) {
      throw new BadRequestException(
        `dayKey must match YYYY-MM-DD format, received: "${value}"`,
      );
    }
    return value;
  }
}
