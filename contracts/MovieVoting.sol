// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MovieVoting {
    enum VotingState {
        NotStarted,
        Ongoing,
        Finished
    }

    struct Poll {
        address creator;
        string[] movies;
        mapping(string => bool) movieExists;
        VotingState state;
        uint endTime;
        string winningMovie;
    }

    mapping(uint => Poll) private polls;
    mapping(uint => mapping(string => uint)) private pollVotes;
    mapping(uint => mapping(address => bool)) private pollHasVoted;
    uint private pollCount;

    error PollNotFound(uint pollId);
    error VotingNotStarted(uint pollId);
    error VotingPeriodEnded(uint pollId);
    error AlreadyVoted(uint pollId);
    error InvalidMovie(uint pollId, string movie);

    event PollCreated(
        uint pollId,
        address creator,
        string[] movies,
        uint endTime
    );
    event VoteCast(uint pollId, address voter, string movie);
    event VotingEnded(uint pollId, string winningMovie);

    modifier onlyPollCreator(uint pollId) {
        if (msg.sender != polls[pollId].creator)
            revert("Only poll creator can perform this action");
        _;
    }

    modifier pollExists(uint pollId) {
        if (pollId >= pollCount) revert PollNotFound(pollId);
        _;
    }

    modifier votingOngoing(uint pollId) {
        Poll storage poll = polls[pollId];
        if (poll.state != VotingState.Ongoing) revert VotingNotStarted(pollId);
        _;
    }

    constructor() {
        pollCount = 0;
    }

    receive() external payable {}

    fallback() external payable {
        revert("Invalid call");
    }

    function createPoll(
        string[] memory _movies,
        uint _votingDuration
    ) external {
        require(_movies.length > 1, "At least two movies required");

        Poll storage newPoll = polls[pollCount];
        newPoll.creator = msg.sender;
        newPoll.movies = _movies;
        newPoll.state = VotingState.NotStarted;
        newPoll.endTime = block.timestamp + _votingDuration;

        for (uint i = 0; i < _movies.length; i++) {
            newPoll.movieExists[_movies[i]] = true;
        }

        emit PollCreated(pollCount, msg.sender, _movies, newPoll.endTime);
        pollCount++;
    }

    function startVoting(
        uint pollId
    ) external pollExists(pollId) onlyPollCreator(pollId) {
        Poll storage poll = polls[pollId];
        require(
            poll.state == VotingState.NotStarted,
            "Voting has already started or ended"
        );
        poll.state = VotingState.Ongoing;
    }

    function vote(
        uint pollId,
        string memory movie
    ) external pollExists(pollId) votingOngoing(pollId) {
        if (pollHasVoted[pollId][msg.sender]) revert AlreadyVoted(pollId);

        Poll storage poll = polls[pollId];
        require(block.timestamp < poll.endTime, "Voting period is over");

        // Optimization 3: Check if movie exists using mapping
        if (!poll.movieExists[movie]) revert InvalidMovie(pollId, movie);

        pollVotes[pollId][movie]++;
        pollHasVoted[pollId][msg.sender] = true;

        emit VoteCast(pollId, msg.sender, movie);
    }

    function endVoting(
        uint pollId
    ) external pollExists(pollId) onlyPollCreator(pollId) {
        Poll storage poll = polls[pollId];
        require(
            poll.state == VotingState.Ongoing,
            "Voting not started or already ended"
        );
        require(block.timestamp >= poll.endTime, "Voting period is not over");

        poll.state = VotingState.Finished;
        assert(poll.state == VotingState.Finished);

        string memory winningMovie = "";
        uint highestVotes = 0;

        string[] memory movies = poll.movies;

        for (uint i = 0; i < movies.length; ++i) {
            if (pollVotes[pollId][movies[i]] > highestVotes) {
                highestVotes = pollVotes[pollId][movies[i]];
                winningMovie = movies[i];
            }
        }

        poll.winningMovie = winningMovie;
        emit VotingEnded(pollId, winningMovie);
    }

    function getWinningMovie(
        uint pollId
    ) external view pollExists(pollId) returns (string memory) {
        Poll storage poll = polls[pollId];
        require(poll.state == VotingState.Finished, "Voting not ended yet");
        return poll.winningMovie;
    }

    function getPollEndTime(
        uint pollId
    ) external view pollExists(pollId) returns (uint) {
        return polls[pollId].endTime;
    }
}
