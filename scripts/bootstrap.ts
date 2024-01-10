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
} from "@solana/web3.js";
import { Big, BigUtils, bs58 } from "@switchboard-xyz/common";
import { OracleJob } from "@switchboard-xyz/common";
import * as sb from "@switchboard-xyz/solana.js";
import { toBufferLE } from "bigint-buffer";
import * as crypto from "crypto";
import * as fs from "fs";
const assert = require("assert");

const walletFile = "your wallet file json here";
// example "/Users/mgild/switchboard_environments_v2/devnet/upgrade_authority/test.json"
const payerFile = "your payer file json here";
let PID = new PublicKey("sbattyXrzedoNATfc4L31wC9Mhxsi1BmFhTiN8gDshx");
// PID = new PublicKey("CR1hCrkKveeWrYYs5kk7rasRM2AH1vZy8s8fn42NBwkq");
const RPC_URL = "https://api.devnet.solana.com";

async function fetchLatestSlotHash(
    connection: Connection
): Promise<[bigint, string]> {
    const slotHashesSysvarKey = new PublicKey(
        "SysvarS1otHashes111111111111111111111111111"
    );
    const accountInfo = await connection.getAccountInfo(slotHashesSysvarKey, {
        commitment: "confirmed",
        dataSlice: { length: 40, offset: 8 },
    });
    let buffer = accountInfo!.data;
    const slotNumber = buffer.readBigUInt64LE();
    buffer = buffer.slice(8);
    return [slotNumber, bs58.encode(buffer)];
}

async function initWalletFromFile(filePath: string): Promise<anchor.Wallet> {
    // Read the file
    const secretKeyString: string = fs.readFileSync(filePath, {
        encoding: "utf8",
    });
    const secretKey: Uint8Array = Uint8Array.from(JSON.parse(secretKeyString));

    // Create a keypair from the secret key
    const keypair: Keypair = Keypair.fromSecretKey(secretKey);

    // Create a wallet
    const wallet: anchor.Wallet = new anchor.Wallet(keypair);

    return wallet;
}

async function initKeypairFromFile(filePath: string): Promise<Keypair> {
    // Read the file
    const secretKeyString: string = fs.readFileSync(filePath, {
        encoding: "utf8",
    });
    const secretKey: Uint8Array = Uint8Array.from(JSON.parse(secretKeyString));

    // Create a keypair from the secret key
    const keypair: Keypair = Keypair.fromSecretKey(secretKey);

    return keypair;
}

async function keypairFromJson(secretKeyString: string): Promise<Keypair> {
    const secretKey: Uint8Array = Uint8Array.from(JSON.parse(secretKeyString));

    // Create a keypair from the secret key
    return Keypair.fromSecretKey(secretKey);
}

export function logEnvVariables(
    env: Array<[string, string | anchor.web3.PublicKey]>,
    pre = "Make sure to add the following to your .env file:"
) {
    console.log(
        `\n${pre}\n\t${env
            .map(([key, value]) => `${key.toUpperCase()}=${value}`)
            .join("\n\t")}\n`
    );
}

(async () => {
    const ORACLE_IP = "127.0.0.1";

    const PID = sb.SB_ON_DEMAND_PID;
    const connection = new Connection(RPC_URL, "confirmed");

    const wallet = await initWalletFromFile(walletFile);
    const devnetPayer = await initKeypairFromFile(payerFile);
    const provider = new anchor.AnchorProvider(connection, wallet, {});
    const idl = await anchor.Program.fetchIdl(PID, provider);
    const program = new anchor.Program(idl!, PID, provider);
    const switchboardProgram = sb.SwitchboardProgram.from(
        connection,
        devnetPayer,
        sb.SB_V2_PID,
        PID
    );

    const [slotNumber, slotHash] = await fetchLatestSlotHash(connection);
    const bootstrappedQueue =
        (await sb.AttestationQueueAccount.bootstrapNewQueue(
            switchboardProgram
        )) as any;
    console.log(bootstrappedQueue);

    const attestationQueueAccount = bootstrappedQueue.attestationQueue.account;
    const verifierOracleAccount = bootstrappedQueue.verifier.account;
    const quoteKeypair2 = Keypair.generate();

    const [verifier2, signature] = await attestationQueueAccount.createVerifier(
        {
            createPermissions: true,
            keypair: quoteKeypair2,
            enable: true,
            queueAuthorityPubkey: devnetPayer.publicKey,
            authority: devnetPayer.publicKey,
            queueAccount: attestationQueueAccount.publicKey,
            registryKey: new Uint8Array(64).fill(0),
        }
    );
    console.log(verifier2.publicKey);

    logEnvVariables([
        [
            "SWITCHBOARD_ATTESTATION_QUEUE_KEY",
            attestationQueueAccount.publicKey,
        ],
        ["SWITCHBOARD_VERIFIER_ORACLE_KEY", verifierOracleAccount.publicKey],
        ["SWITCHBOARD_VERIFIER_ORACLE_KEY2", verifier2.publicKey.toString()],
    ]);

    const y = bootstrappedQueue.signatures.map((s: any, i: any): any => {
        return { name: `bootstrap_queue #${i + 1}`, tx: s };
    });
    console.log(y);
    return;
})();
