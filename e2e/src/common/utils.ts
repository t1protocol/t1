import {BlockTag, ethers} from "ethers";
import {TypedContractEvent, TypedDeferredTopicFilter, TypedEventLog} from "../typechain/common";
import {L1StandardERC20Gateway, L1T1Messenger, L2StandardERC20Gateway, L2T1Messenger} from "../typechain";

export function etherToWei(amount: string): bigint {
  return ethers.parseEther(amount.toString());
}

export function weiToEther(amount: string) : string {
  return ethers.formatEther(amount.toString());
}

export const wait = (timeout: number) => new Promise((resolve) => setTimeout(resolve, timeout));

export async function getEvents<
  TContract extends L1T1Messenger | L2T1Messenger | L1StandardERC20Gateway | L2StandardERC20Gateway,
  TEvent extends TypedContractEvent,
>(
  contract: TContract,
  eventFilter: TypedDeferredTopicFilter<TEvent>,
  fromBlock?: BlockTag,
  toBlock?: BlockTag,
  criteria?: (events: TypedEventLog<TEvent>[]) => Promise<TypedEventLog<TEvent>[]>,
): Promise<Array<TypedEventLog<TEvent>>> {
  const events = await contract.queryFilter(
    eventFilter,
    fromBlock as string | number | undefined,
    toBlock as string | number | undefined,
  );

  if (criteria) {
    return await criteria(events);
  }

  return events;
}

export async function waitForEvents<
  TContract extends L1T1Messenger | L2T1Messenger | L1StandardERC20Gateway | L2StandardERC20Gateway,
  TEvent extends TypedContractEvent,
>(
  contract: TContract,
  eventFilter: TypedDeferredTopicFilter<TEvent>,
  pollingInterval: number = 500,
  fromBlock?: BlockTag,
  toBlock?: BlockTag,
  criteria?: (events: TypedEventLog<TEvent>[]) => Promise<TypedEventLog<TEvent>[]>,
): Promise<TypedEventLog<TEvent>[]> {
  let events = await getEvents(contract, eventFilter, fromBlock, toBlock, criteria);
  while (events.length === 0) {
    events = await getEvents(contract, eventFilter, fromBlock, toBlock, criteria);
    await wait(pollingInterval);
  }
  return events;
}

