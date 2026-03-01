import asyncio
from grpc import aio
import han_dog_message as msg


async def main():
    async with aio.insecure_channel("127.0.0.1:13145") as channel:
        stub = msg.CmsStub(channel)
        response = await stub.Enable(msg.Empty())
        print(f"Enable response received {response}")
        async for r in stub.ListenStrategy(msg.Empty()):
            print(f"Strategy: {r}")


if __name__ == "__main__":
    asyncio.run(main())
