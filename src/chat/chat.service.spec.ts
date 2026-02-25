import { Test, TestingModule } from '@nestjs/testing';
import { ChatService } from './chat.service';
import { ChatRepository } from './chat.repository';
import { AiService } from '../ai/ai.service';
import { ServiceUnavailableException } from '@nestjs/common';

const mockMessage = (role: string, text: string) => ({
  id: 'uuid-1',
  userId: null,
  dayKey: '2026-02-25',
  role,
  text,
  timestamp: new Date(),
  clientMessageId: null,
});

describe('ChatService', () => {
  let service: ChatService;
  let repo: jest.Mocked<ChatRepository>;
  let ai: jest.Mocked<AiService>;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ChatService,
        {
          provide: ChatRepository,
          useValue: {
            findAssistantReplyAfterClientId: jest.fn().mockResolvedValue(null),
            createMessage: jest.fn().mockImplementation((data) => ({
              ...mockMessage(data.role, data.text),
              id: 'new-uuid',
            })),
            getByDayKey: jest.fn().mockResolvedValue([]),
          },
        },
        {
          provide: AiService,
          useValue: {
            chat: jest.fn().mockResolvedValue('How did that make you feel?'),
          },
        },
      ],
    }).compile();

    service = module.get<ChatService>(ChatService);
    repo    = module.get(ChatRepository);
    ai      = module.get(AiService);
  });

  it('persists user message before calling AI', async () => {
    await service.sendMessage({ dayKey: '2026-02-25', userText: 'Hello' }, null);

    // createMessage called first with 'user', then with 'assistant'
    expect(repo.createMessage).toHaveBeenCalledTimes(2);
    const firstCall = repo.createMessage.mock.calls[0][0];
    expect(firstCall.role).toBe('user');
    expect(firstCall.text).toBe('Hello');
  });

  it('returns the assistant reply', async () => {
    const result = await service.sendMessage(
      { dayKey: '2026-02-25', userText: 'Hello' },
      null,
    );
    expect(result.assistantMessage.role).toBe('assistant');
    expect(result.assistantMessage.text).toBe('How did that make you feel?');
  });

  it('returns cached assistant reply on idempotent send', async () => {
    const cached = mockMessage('assistant', 'Cached reply');
    repo.findAssistantReplyAfterClientId.mockResolvedValue(cached);

    const result = await service.sendMessage(
      { dayKey: '2026-02-25', userText: 'Hello', clientMessageId: 'client-1' },
      null,
    );

    // Should NOT call createMessage or AI
    expect(repo.createMessage).not.toHaveBeenCalled();
    expect(ai.chat).not.toHaveBeenCalled();
    expect(result.assistantMessage.text).toBe('Cached reply');
  });

  it('still saves user message if AI throws', async () => {
    ai.chat.mockRejectedValue(new ServiceUnavailableException());

    await expect(
      service.sendMessage({ dayKey: '2026-02-25', userText: 'Hello' }, null),
    ).rejects.toThrow(ServiceUnavailableException);

    // User message must have been persisted before the AI call failed
    expect(repo.createMessage).toHaveBeenCalledWith(
      expect.objectContaining({ role: 'user', text: 'Hello' }),
    );
  });

  it('passes prior messages to the AI in order', async () => {
    const prior = [
      mockMessage('user', 'First'),
      mockMessage('assistant', 'Reply'),
    ];
    // Simulate DB returning all 3 messages after the user message is persisted
    repo.getByDayKey.mockResolvedValue([...prior, mockMessage('user', 'Second')]);

    await service.sendMessage({ dayKey: '2026-02-25', userText: 'Second' }, null);

    const aiPayload = ai.chat.mock.calls[0][0];
    expect(aiPayload).toHaveLength(3); // 2 prior + new user message included by getByDayKey
  });
});
