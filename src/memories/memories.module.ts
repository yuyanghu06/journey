import { Module } from '@nestjs/common';
import { MemoriesService } from './memories.service';
import { MemoriesController } from './memories.controller';
import { MemoriesRepository } from './memories.repository';

@Module({
  providers: [MemoriesService, MemoriesRepository],
  controllers: [MemoriesController],
  exports: [MemoriesRepository],
})
export class MemoriesModule {}
