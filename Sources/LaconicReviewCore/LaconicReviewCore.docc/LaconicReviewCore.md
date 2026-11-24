# ``LaconicReviewCore``

The provider-neutral core of laconic-review: review-domain types plus the forge-connection seam.

## Overview

`LaconicReviewCore` is the contract the review skill conforms to. Its public types — and the
``ReviewHost`` protocol the forge connections conform to — are the *interaction standard*;
the skill reads this catalog's symbol graph to learn what to emit and self-heals when it
changes. Keep the doc comments here accurate: they are the spec, not decoration.

The split is deliberate: review intelligence and the report format are neutral, and **only**
the per-forge connection targets know their API — `GitLabConnection` (GitLabKit) and
`GitHubConnection` (hand-written REST+GraphQL) each live in their own module, so provider
dependencies never leak into the core or into each other.

## Topics

### Project Direction

- <doc:Design>
- <doc:Roadmap>
- <doc:TechDebt>

### Connecting

- ``HostConfig``
- ``ProjectContext``
- ``ReviewHost``
- ``ReviewHostKind``
- ``ConnectionError``

### Review domain

- ``MergeRequestSummary``
- ``MergeRequestState``
- ``DiffRefs``
- ``DiscussionSummary``
- ``Identity``

### Resolving a branch to an MR

- ``MergeRequestResolver``
- ``MergeRequestResolution``
- ``AmbiguityReason``

### The report (markdown SSOT)

The human-editable markdown is the source of truth; machine fields ride in `<!-- review … -->`
and `<!-- finding … -->` HTML comments. Position SHAs are never persisted — `publish` fetches
`diff_refs` fresh — but the review anchor may stamp `head_sha`, the revision reviewed, which
publish compares against the current head before trusting out-of-hunk anchors.

- ``ReportParser``
- ``ReviewReport``
- ``ReviewHeader``
- ``Finding``
- ``FindingScope``
- ``LineSide``
- ``Position``

### Publishing (idempotent)

`publish` posts each open, not-yet-published finding as a discussion (line-anchored via
``Position`` resolved against the MR diff by ``AnchorResolver``, or general), recording
the result in the ``PublishLedger`` so re-runs are safe.

- ``ReviewHost/postDiscussion(iid:body:position:diffRefs:)``
- ``ReviewHost/mergeRequestDiffs(iid:)``
- ``ReviewHost/resolveThread(iid:discussionID:resolved:)``
- ``DiffParser``
- ``AnchorResolver``
- ``ResolvedPosition``
- ``FileDiff``
- ``FileLineMap``
- ``DiffHunk``
- ``DiffLine``
- ``OldDiffLine``
- ``PostedDiscussion``
- ``PublishLedger``
- ``PublishedThread``
