// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MovieVoting {
    // Enum to represent voting state
    enum VotingState {
        NotStarted,
        Ongoing,
        Finished
    }

    // Struct to represent a movie poll
    struct Poll {
        address creator;
        string[] movies;
        mapping(string => bool) movieExists; // New mapping to check movie existence
        VotingState state;
        uint endTime;
        string winningMovie;
    }

    // Mapping to store all polls by their ID
    mapping(uint => Poll) private polls;
    mapping(uint => mapping(string => uint)) private pollVotes; // Votes for each movie in a poll
    mapping(uint => mapping(address => bool)) private pollHasVoted; // Voting status of each address
    uint private pollCount;
    bool private locked; // State variable for reentrancy guard

    // Custom errors
    error PollNotFound(uint pollId);
    error VotingNotStarted(uint pollId);
    error VotingPeriodEnded(uint pollId);
    error AlreadyVoted(uint pollId);
    error InvalidMovie(uint pollId, string movie);

    // Events
    event PollCreated(
        uint pollId,
        address creator,
        string[] movies,
        uint endTime
    );
    event VoteCast(uint pollId, address voter, string movie);
    event VotingEnded(uint pollId, string winningMovie);

    // Modifiers
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

    // Reentrancy guard modifier
    modifier noReentrancy() {
        require(!locked, "Reentrancy is not allowed");
        locked = true;
        _;
        locked = false;
    }

    constructor() {
        pollCount = 0;
    }

    // Receive function to accept Ether
    receive() external payable {}

    // Fallback function
    fallback() external payable {
        revert("Invalid call");
    }

    // Function to create a new poll
    function createPoll(
        string[] memory _movies, // Use memory to handle dynamic arrays
        uint _votingDuration
    ) external {
        require(_movies.length > 1, "At least two movies required");

        Poll storage newPoll = polls[pollCount];
        newPoll.creator = msg.sender;
        newPoll.movies = _movies;
        newPoll.state = VotingState.NotStarted;
        newPoll.endTime = block.timestamp + _votingDuration;

        // Optimization 3: Use mapping to quickly check movie existence
        for (uint i = 0; i < _movies.length; i++) {
            newPoll.movieExists[_movies[i]] = true;
        }

        emit PollCreated(pollCount, msg.sender, _movies, newPoll.endTime);
        pollCount++;
    }

    // Function to start voting for a poll
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

    // Function to cast a vote
    function vote(
        uint pollId,
        string memory movie
    ) external pollExists(pollId) votingOngoing(pollId) noReentrancy {
        if (pollHasVoted[pollId][msg.sender]) revert AlreadyVoted(pollId);

        Poll storage poll = polls[pollId];
        require(block.timestamp < poll.endTime, "Voting period is over");

        // Optimization 3: Check if movie exists using mapping
        if (!poll.movieExists[movie]) revert InvalidMovie(pollId, movie);

        pollVotes[pollId][movie]++;
        pollHasVoted[pollId][msg.sender] = true;

        emit VoteCast(pollId, msg.sender, movie);
    }

    // Function to end voting and determine the winner
    function endVoting(
        uint pollId
    ) external pollExists(pollId) onlyPollCreator(pollId) noReentrancy {
        Poll storage poll = polls[pollId];
        require(
            poll.state == VotingState.Ongoing,
            "Voting not started or already ended"
        );
        require(block.timestamp >= poll.endTime, "Voting period is not over");

        poll.state = VotingState.Finished;
        assert(poll.state == VotingState.Finished); // Assert to ensure state has been updated correctly

        string memory winningMovie = "";
        uint highestVotes = 0;

        // Optimization 1: Use memory instead of storage to optimize gas
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

    // Function to get the winner of a poll
    function getWinningMovie(
        uint pollId
    ) external view pollExists(pollId) returns (string memory) {
        Poll storage poll = polls[pollId];
        require(poll.state == VotingState.Finished, "Voting not ended yet");
        return poll.winningMovie;
    }

    // Function to get the end time of a poll
    function getPollEndTime(
        uint pollId
    ) external view pollExists(pollId) returns (uint) {
        return polls[pollId].endTime;
    }
}
