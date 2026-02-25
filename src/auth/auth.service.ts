import {
  Injectable,
  ConflictException,
  UnauthorizedException,
  NotFoundException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../db/prisma.service';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';

const ACCESS_EXPIRY  = '15m';
const REFRESH_EXPIRY = '30d';
const REFRESH_EXPIRY_MS = 30 * 24 * 60 * 60 * 1000;

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  // ---------------------------------------------------------------------------
  // Register
  // ---------------------------------------------------------------------------

  async register(dto: RegisterDto) {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('Email already registered');

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const user = await this.prisma.user.create({
      data: { email: dto.email, passwordHash },
      select: { id: true, email: true },
    });

    const tokens = await this.issueTokens(user.id, user.email);
    return { user, tokens };
  }

  // ---------------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------------

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (!user) throw new UnauthorizedException('Invalid credentials');

    const valid = await bcrypt.compare(dto.password, user.passwordHash);
    if (!valid) throw new UnauthorizedException('Invalid credentials');

    const tokens = await this.issueTokens(user.id, user.email);
    return { user: { id: user.id, email: user.email }, tokens };
  }

  // ---------------------------------------------------------------------------
  // Logout — invalidates the refresh token
  // ---------------------------------------------------------------------------

  async logout(refreshToken: string) {
    // Best-effort delete — don't throw if token not found
    await this.prisma.refreshToken.deleteMany({ where: { token: refreshToken } });
  }

  // ---------------------------------------------------------------------------
  // Refresh — rotate token pair
  // ---------------------------------------------------------------------------

  async refresh(refreshToken: string) {
    const record = await this.prisma.refreshToken.findUnique({
      where: { token: refreshToken },
      include: { user: { select: { id: true, email: true } } },
    });

    if (!record || record.expiresAt < new Date()) {
      if (record) await this.prisma.refreshToken.delete({ where: { id: record.id } });
      throw new UnauthorizedException('Refresh token expired or invalid');
    }

    // Rotate: delete old token, issue new pair
    await this.prisma.refreshToken.delete({ where: { id: record.id } });
    const tokens = await this.issueTokens(record.user.id, record.user.email);
    return { tokens };
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private async issueTokens(userId: string, email: string) {
    const payload = { sub: userId, email };

    const [accessToken, refreshToken] = await Promise.all([
      this.jwt.signAsync(payload, {
        secret: process.env.JWT_ACCESS_SECRET ?? 'dev-access-secret',
        expiresIn: ACCESS_EXPIRY,
      }),
      this.jwt.signAsync(payload, {
        secret: process.env.JWT_REFRESH_SECRET ?? 'dev-refresh-secret',
        expiresIn: REFRESH_EXPIRY,
      }),
    ]);

    // Persist refresh token for rotation / revocation
    await this.prisma.refreshToken.create({
      data: {
        userId,
        token: refreshToken,
        expiresAt: new Date(Date.now() + REFRESH_EXPIRY_MS),
      },
    });

    return { accessToken, refreshToken };
  }
}
