import { DayKeyPipe } from './daykey.pipe';
import { BadRequestException } from '@nestjs/common';

describe('DayKeyPipe', () => {
  const pipe = new DayKeyPipe();

  it('accepts a valid YYYY-MM-DD string', () => {
    expect(pipe.transform('2026-02-25')).toBe('2026-02-25');
  });

  it('accepts the first day of a month', () => {
    expect(pipe.transform('2026-01-01')).toBe('2026-01-01');
  });

  it('rejects a date with wrong separator', () => {
    expect(() => pipe.transform('2026/02/25')).toThrow(BadRequestException);
  });

  it('rejects a partial date', () => {
    expect(() => pipe.transform('2026-02')).toThrow(BadRequestException);
  });

  it('rejects an empty string', () => {
    expect(() => pipe.transform('')).toThrow(BadRequestException);
  });

  it('rejects a date with letters', () => {
    expect(() => pipe.transform('abcd-ef-gh')).toThrow(BadRequestException);
  });

  it('rejects month 00', () => {
    expect(() => pipe.transform('2026-00-15')).toThrow(BadRequestException);
  });

  it('rejects month 13', () => {
    expect(() => pipe.transform('2026-13-01')).toThrow(BadRequestException);
  });

  it('rejects day 00', () => {
    expect(() => pipe.transform('2026-02-00')).toThrow(BadRequestException);
  });

  it('rejects day 32', () => {
    expect(() => pipe.transform('2026-01-32')).toThrow(BadRequestException);
  });
});
