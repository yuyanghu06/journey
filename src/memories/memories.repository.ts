import { Injectable } from '@nestjs/common';
import { PrismaService } from '../db/prisma.service';
import { Memory } from '@prisma/client';

@Injectable()
export class MemoriesRepository {
  constructor(private readonly prisma: PrismaService) {}

  async create(data: {
    userId: string | null;
    title: string;
    text: string;
  }): Promise<Memory> {
    return this.prisma.memory.create({ data });
  }

  async findAll(userId: string | null): Promise<Memory[]> {
    return this.prisma.memory.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async delete(id: string, userId: string | null): Promise<Memory | null> {
    const existing = await this.prisma.memory.findFirst({ where: { id, userId } });
    if (!existing) return null;
    return this.prisma.memory.delete({ where: { id } });
  }
}
