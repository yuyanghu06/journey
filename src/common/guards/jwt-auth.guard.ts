import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/**
 * Convenience wrapper around NestJS's JWT AuthGuard.
 * Apply with @UseGuards(JwtAuthGuard) on any protected controller or route.
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
