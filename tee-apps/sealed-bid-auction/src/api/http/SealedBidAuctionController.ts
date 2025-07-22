import type {Request, Response} from "express";

export class SealedBidAuctionController {

    async open(req: Request, res: Response): Promise<void> {
        res.status(501);
    }
}