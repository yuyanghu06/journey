import { Controller, Get, Logger } from '@nestjs/common';

@Controller('health')
export class HealthController {
  private readonly logger = new Logger(HealthController.name);

  @Get()
  check() {
    const response = { status: 'ok', timestamp: new Date().toISOString() };
    this.logger.log(`Health check response: ${JSON.stringify(response)}`);
    return response;
  }
}
