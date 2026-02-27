import { Injectable, NotFoundException } from '@nestjs/common';
import { MemoriesRepository } from './memories.repository';
import { CreateMemoryDto } from './dto/create-memory.dto';
import { Memory } from '@prisma/client';

@Injectable()
export class MemoriesService {
  constructor(private readonly repo: MemoriesRepository) {}

  create(dto: CreateMemoryDto, userId: string | null): Promise<Memory> {
    return this.repo.create({ userId, title: dto.title, text: dto.text });
  }

  findAll(userId: string | null): Promise<Memory[]> {
    return this.repo.findAll(userId);
  }

  async delete(id: string, userId: string | null): Promise<Memory> {
    const deleted = await this.repo.delete(id, userId);
    if (!deleted) throw new NotFoundException(`Memory ${id} not found`);
    return deleted;
  }
}
