import { OwnershipTransferred } from "../generated/templates/ReceiptVault/Ownable";
import { ContractKind, recordOwnershipTransfer } from "./lib/contract";

export function handleReceiptVaultOwnershipTransferred(
  event: OwnershipTransferred,
): void {
  recordOwnershipTransfer(
    ContractKind.RECEIPT_VAULT,
    event,
    event.params.previousOwner,
    event.params.newOwner,
  );
}
