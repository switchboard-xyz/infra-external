import * as anchor from "@coral-xyz/anchor";
import * as spl from "@solana/spl-token";
import type { AccountInfo, AccountMeta } from "@solana/web3.js";
import {
  AddressLookupTableProgram,
  Connection,
  Keypair,
  MessageV0,
  PublicKey,
  sendAndConfirmTransaction,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
  AddressLookupTableAccount,
} from "@solana/web3.js";
var resolve = require("resolve-dir");
import { Big, BigUtils, bs58 } from "@switchboard-xyz/common";
import { OracleJob } from "@switchboard-xyz/common";
import * as sb from "@switchboard-xyz/on-demand";
import { toBufferLE } from "bigint-buffer";
import * as crypto from "crypto";
import * as fs from "fs";
const assert = require("assert");
const yargs = require("yargs/yargs");
import {
  InstructionUtils,
  PullFeed,
  Queue,
  RecentSlotHashes,
} from "@switchboard-xyz/on-demand";

// ts-node bootstrap.ts --queueKey=7n7CSKBhqxM9m9YyLPn7cF6vXvxtZAWMBW42ior8qode --guardianQueue=F4pXZNjaaNmGwXzBhoxs5yaH6f6RKKkj5qgCZKPF9rjg --payerPath=/home/scottk/workspace/creds/devops-keypair.json

let argv = yargs(process.argv).options({
  queueKey: {
    type: "string",
    describe: "Queue to put pull oracle on",
    demand: false,
    default: "",
  },
  guardianQueue: {
    type: "string",
    describe: "Queue to put guardian oracle on",
    demand: false,
    default: "",
  },
  initQueues: {
    type: "boolean",
    describe: "Initialize new queues",
    demand: false,
    default: false,
  },
  payerPath: {
    type: "string",
    describe: "Path to payer keypair",
    demand: true,
  },
}).argv;

async function sendIx(
  program: anchor.Program,
  ix: TransactionInstruction,
  signers: Array<Keypair>
) {
  const tx = await InstructionUtils.asV0Tx(program, [ix], []);
  for (const signer of signers) {
    tx.sign([signer]);
  }
  const sig = await program.provider.connection.sendTransaction(tx);
  console.log(`signature: ${sig}`);
}

function keypairFromJson(secretKeyString: string): Keypair {
  const secretKey: Uint8Array = Uint8Array.from(JSON.parse(secretKeyString));
  return Keypair.fromSecretKey(secretKey);
}

function initKeypairFromFile(filePath: string): Keypair {
  const secretKeyString = fs.readFileSync(filePath, { encoding: "utf8" });
  return keypairFromJson(secretKeyString);
}

(async () => {
  let PID;
  PID = sb.SB_ON_DEMAND_PID;
  const connection = new Connection(
    "https://api.devnet.solana.com",
    "confirmed"
  );
  const devnetPayer = initKeypairFromFile(
    resolve(argv.payerPath || "./payer.json")
  );
  const wallet = new anchor.Wallet(devnetPayer);
  const provider = new anchor.AnchorProvider(connection, wallet, {});
  const idl = await anchor.Program.fetchIdl(PID, provider);
  const program = new anchor.Program(idl!, PID, provider);
  let queueKey = argv.queueKey;
  let guardianQueueKey = argv.guardianQueue;
  console.log(`Queue: ${queueKey}`);
  console.log(`GuardianQueue: ${guardianQueueKey}`);
  if (argv.initQueues) {
    try {
      const [state, stateInitSig] = await sb.State.create(program);
      console.log(`State: ${state.pubkey.toBase58()} Sig: ${stateInitSig}`);
    } catch (e) { }
    const state = new sb.State(program);
    const [queue, queueCreateSig] = await sb.Queue.create(program, {});
    console.log(`Queue: ${queue.pubkey.toBase58()} Sig: ${queueCreateSig}`);
    queueKey = queue.pubkey.toBase58();
    const [guardianQueue, guardianQueueCreateSig] = await sb.Queue.create(
      program,
      {}
    );
    guardianQueueKey = guardianQueue.pubkey.toBase58();
    console.log(
      `GuardianQueue: ${queue.pubkey.toBase58()} Sig: ${guardianQueueCreateSig}`
    );
    const setConfigIx = await state.setConfigsIx({
      guardianQueue: guardianQueue.pubkey,
      newAuthority: devnetPayer.publicKey,
      minQuoteVerifyVotes: new anchor.BN(1),
    });
    const setConfigTx = await InstructionUtils.asV0Tx(program, [setConfigIx]);
    setConfigTx.sign([devnetPayer]);
    const setConfigSig = await connection.sendTransaction(setConfigTx);
    console.log(`Set Config Sig: ${setConfigSig}`);
  }
  const queue = new sb.Queue(program, new PublicKey(queueKey));
  const guardianQueue = new sb.Queue(program, new PublicKey(guardianQueueKey));
  const stateAccount = new sb.State(program);
  const state = new sb.State(program);
  const [oracle1, oracleCreateSig1] = await sb.Oracle.create(program, {
    queue: queue.pubkey,
  });
  const [guardianOracle1, goracleCreateSig1] = await sb.Oracle.create(program, {
    queue: guardianQueue.pubkey,
  });
  if (argv.initQueues) {
    await sendIx(
      program,
      await sb.Permission.setIx(program, {
        authority: devnetPayer.publicKey,
        grantee: oracle1.pubkey,
        granter: queue.pubkey,
        enable: true,
        permission: sb.SwitchboardPermission.PermitOracleHeartbeat,
      }),
      [devnetPayer]
    );
    await sendIx(
      program,
      await sb.Permission.setIx(program, {
        authority: devnetPayer.publicKey,
        granter: guardianQueue.pubkey,
        grantee: guardianOracle1.pubkey,
        enable: true,
        permission: sb.SwitchboardPermission.PermitOracleHeartbeat,
      }),
      [devnetPayer]
    );
  }

  console.log(`
  export QUEUE=${queue.pubkey.toBase58()}
  export GUARDIAN_QUEUE=${guardianQueue.pubkey.toBase58()}
  export STATE=${state.pubkey.toBase58()}
  export PID=${PID.toBase58()}
  export ORACLE1=${oracle1.pubkey.toBase58()}
  export GUARDIAN_ORACLE1=${guardianOracle1.pubkey.toBase58()}
  `);
  return;
})();
