import { Test, TestingModule } from '@nestjs/testing';
import { JournalService } from './journal.service';
import { JournalRepository } from './journal.repository';
import { ChatRepository } from '../chat/chat.repository';
import { AiService } from '../ai/ai.service';

const mockMessage = (role: string, text: string) => ({
  id: 'uuid',
  userId: null,
  dayKey: '2026-02-25',
  role,
  text,
  timestamp: new Date(),
  clientMessageId: null,
});

const mockEntry = (text: string) => ({
  id: 'entry-uuid',
  userId: null,
  dayKey: '2026-02-25',
  text,
  createdAt: new Date(),
  updatedAt: new Date(),
});

describe('JournalService', () => {
  let service: JournalService;
  let journalRepo: jest.Mocked<JournalRepository>;
  let chatRepo: jest.Mocked<ChatRepository>;
  let ai: jest.Mocked<AiService>;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        JournalService,
        {
          provide: JournalRepository,
          useValue: {
            upsert: jest.fn().mockImplementation((_u, _d, text) => mockEntry(text)),
            findByDayKey: jest.fn().mockResolvedValue(null),
          },
        },
        {
          provide: ChatRepository,
          useValue: {
            getByDayKey: jest.fn().mockResolvedValue([
              mockMessage('user', 'Today was really hard.'),
              mockMessage('assistant', 'Tell me more about that.'),
            ]),
          },
        },
        {
          provide: AiService,
          useValue: {
            summarise: jest.fn().mockResolvedValue('Today I reflected on a difficult day.'),
          },
        },
      ],
    }).compile();

    service     = module.get<JournalService>(JournalService);
    journalRepo = module.get(JournalRepository);
    chatRepo    = module.get(ChatRepository);
    ai          = module.get(AiService);
  });

  it('calls AI with conversation text', async () => {
    await service.generate('2026-02-25', null);
    expect(ai.summarise).toHaveBeenCalledWith(
      expect.stringContaining('Today was really hard.'),
    );
  });

  it('calls upsert with the AI-generated text', async () => {
    await service.generate('2026-02-25', null);
    expect(journalRepo.upsert).toHaveBeenCalledWith(
      null,
      '2026-02-25',
      'Today I reflected on a difficult day.',
    );
  });

  it('returns the journalEntry', async () => {
    const result = await service.generate('2026-02-25', null);
    expect(result.journalEntry.text).toBe('Today I reflected on a difficult day.');
  });

  it('upserts (replaces) when an entry already exists', async () => {
    journalRepo.findByDayKey.mockResolvedValue(mockEntry('Old text'));

    await service.generate('2026-02-25', null);

    // Upsert must still be called with new AI text — not the old entry
    expect(journalRepo.upsert).toHaveBeenCalledWith(
      null,
      '2026-02-25',
      'Today I reflected on a difficult day.',
    );
  });
});
