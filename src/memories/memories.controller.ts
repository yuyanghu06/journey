import {
  Controller,
  Get,
  Post,
  Delete,
  Body,
  Param,
  UseGuards,
  Request,
} from '@nestjs/common';
import { MemoriesService } from './memories.service';
import { CreateMemoryDto } from './dto/create-memory.dto';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';

@UseGuards(JwtAuthGuard)
@Controller('memories')
export class MemoriesController {
  constructor(private readonly memoriesService: MemoriesService) {}

  /** POST /memories — create a new memory note */
  @Post()
  create(@Body() dto: CreateMemoryDto, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.memoriesService.create(dto, userId);
  }

  /** GET /memories — list all memories for the current user */
  @Get()
  findAll(@Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.memoriesService.findAll(userId);
  }

  /** DELETE /memories/:id — delete a memory by id */
  @Delete(':id')
  delete(@Param('id') id: string, @Request() req) {
    const userId: string | null = req.user?.id ?? null;
    return this.memoriesService.delete(id, userId);
  }
}
