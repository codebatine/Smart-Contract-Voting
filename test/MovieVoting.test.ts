const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MovieVoting Contract", function () {
    let MovieVoting, movieVoting: any, owner: any, addr1: any, addr2: any;
    
    beforeEach(async function () {
        MovieVoting = await ethers.getContractFactory("MovieVoting");
        [owner, addr1, addr2] = await ethers.getSigners();
        movieVoting = await MovieVoting.deploy();
        await movieVoting.deployed();
    });

    describe("Deployment", function () {
        it("Should deploy with zero polls", async function () {
            await expect(movieVoting.getPollEndTime(0)).to.be.revertedWithCustomError(movieVoting, "PollNotFound");
        });
    });

    describe("Poll Creation", function () {
        it("Should create a poll successfully", async function () {
            await movieVoting.createPoll(["Movie1", "Movie2"], 60 * 60);
            const pollEndTime = await movieVoting.getPollEndTime(0);
            expect(pollEndTime).to.be.instanceOf(ethers.BigNumber);
        });

        it("Should emit PollCreated event", async function () {
            const tx = await movieVoting.createPoll(["Movie1", "Movie2"], 60 * 60);
            const receipt = await tx.wait();
            const event = receipt.events?.find((e: any) => e.event === "PollCreated");
            expect(event).to.not.be.undefined;
            expect(event.args.pollId).to.equal(0);
            expect(event.args.creator).to.equal(owner.address);
            expect(event.args.movies).to.deep.equal(["Movie1", "Movie2"]);
            expect(event.args.endTime).to.be.instanceOf(ethers.BigNumber);
        });

        it("Should revert if less than two movies are provided", async function () {
            await expect(movieVoting.createPoll(["OnlyOneMovie"], 60 * 60)).to.be.revertedWith("At least two movies required");
        });
    });

    describe("Voting", function () {
        beforeEach(async function () {
            await movieVoting.createPoll(["Movie1", "Movie2"], 60 * 60);
        });

        it("Should start voting correctly", async function () {
            await movieVoting.startVoting(0);
            const pollEndTime = await movieVoting.getPollEndTime(0);
            expect(pollEndTime).to.be.instanceOf(ethers.BigNumber);
        });

        it("Should revert if non-creator tries to start voting", async function () {
            await expect(movieVoting.connect(addr1).startVoting(0)).to.be.revertedWith("Only poll creator can perform this action");
        });

        it("Should allow a valid vote", async function () {
            await movieVoting.startVoting(0);
            await movieVoting.connect(addr1).vote(0, "Movie1");
            await expect(movieVoting.getWinningMovie(0)).to.be.revertedWith("Voting not ended yet");
        });

        it("Should revert if voting has not started", async function () {
            await expect(movieVoting.connect(addr1).vote(0, "Movie1")).to.be.revertedWithCustomError(movieVoting, "VotingNotStarted");
        });

        it("Should revert if voting period is over", async function () {
            await movieVoting.startVoting(0);
            await ethers.provider.send("evm_increaseTime", [60 * 60]);
            await ethers.provider.send("evm_mine");
            await expect(movieVoting.connect(addr1).vote(0, "Movie1")).to.be.revertedWith("Voting period is over");
        });

        it("Should revert if a user votes more than once", async function () {
            await movieVoting.startVoting(0);
            await movieVoting.connect(addr1).vote(0, "Movie1");
            await expect(movieVoting.connect(addr1).vote(0, "Movie2")).to.be.revertedWithCustomError(movieVoting, "AlreadyVoted");
        });

        it("Should revert if voting for a non-existent movie", async function () {
            await movieVoting.startVoting(0);
            await expect(movieVoting.connect(addr1).vote(0, "NonExistentMovie")).to.be.revertedWithCustomError(movieVoting, "InvalidMovie");
        });

        it("Should correctly end voting and determine a winner", async function () {
            await movieVoting.startVoting(0);
            await movieVoting.connect(addr1).vote(0, "Movie1");
            await movieVoting.connect(addr2).vote(0, "Movie2");
            await ethers.provider.send("evm_increaseTime", [60 * 60]);
            await ethers.provider.send("evm_mine");
            await movieVoting.endVoting(0);
            const winningMovie = await movieVoting.getWinningMovie(0);
            expect(winningMovie).to.equal("Movie1");
        });

        it("Should revert if trying to end voting before the period is over", async function () {
            await movieVoting.startVoting(0);
            await movieVoting.connect(addr1).vote(0, "Movie1");
            await expect(movieVoting.endVoting(0)).to.be.revertedWith("Voting period is not over");
        });

        it("Should revert if trying to end voting when it hasn't started", async function () {
            await expect(movieVoting.endVoting(0)).to.be.revertedWith("Voting not started or already ended");
        });
    });

    describe("Custom Error Handling", function () {
        beforeEach(async function () {
            await movieVoting.createPoll(["Movie1", "Movie2"], 60 * 60);
        });

        it("Should revert with custom errors appropriately", async function () {
            await expect(movieVoting.getWinningMovie(1)).to.be.revertedWithCustomError(movieVoting, "PollNotFound");
        });

        it("Should handle fallback function properly", async function () {
            await expect(owner.sendTransaction({
                to: movieVoting.address,
                data: "0x1234"
            })).to.be.revertedWith("Invalid call");
        });

        it("Should handle receive function properly", async function () {
            await expect(() => 
                owner.sendTransaction({ 
                    to: movieVoting.address, 
                    value: ethers.utils.parseEther("1.0") 
                })
            ).to.changeEtherBalance(movieVoting, ethers.utils.parseEther("1.0"));
        });
    });

    describe("Branch Coverage Tests", function () {
        beforeEach(async function () {
            await movieVoting.createPoll(["Movie1", "Movie2"], 60 * 60);
        });

        it("Should revert if trying to start voting when it is already started", async function () {
            await movieVoting.startVoting(0);
            await expect(movieVoting.startVoting(0)).to.be.revertedWith("Voting has already started or ended");
        });

        it("Should revert if trying to vote when voting hasn't started", async function () {
            await expect(movieVoting.connect(addr1).vote(0, "Movie1")).to.be.revertedWithCustomError(movieVoting, "VotingNotStarted");
        });

        it("Should revert if trying to vote after voting period has ended", async function () {
            await movieVoting.startVoting(0);
            await ethers.provider.send("evm_increaseTime", [60 * 60]);
            await ethers.provider.send("evm_mine");
            await expect(movieVoting.connect(addr1).vote(0, "Movie1")).to.be.revertedWith("Voting period is over");
        });

        it("Should revert if trying to vote for a non-existent movie", async function () {
            await movieVoting.startVoting(0);
            await expect(movieVoting.connect(addr1).vote(0, "NonExistentMovie")).to.be.revertedWithCustomError(movieVoting, "InvalidMovie");
        });

        it("Should revert if trying to end voting when it hasn't started", async function () {
            await expect(movieVoting.endVoting(0)).to.be.revertedWith("Voting not started or already ended");
        });

        it("Should correctly handle state transitions in endVoting", async function () {
            await movieVoting.startVoting(0);
            await movieVoting.connect(addr1).vote(0, "Movie1");
            await ethers.provider.send("evm_increaseTime", [60 * 60]);
            await ethers.provider.send("evm_mine");
            await movieVoting.endVoting(0);
            const winningMovie = await movieVoting.getWinningMovie(0);
            expect(winningMovie).to.equal("Movie1");
        });
    });
});