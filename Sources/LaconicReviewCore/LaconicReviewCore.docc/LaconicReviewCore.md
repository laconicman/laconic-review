# ``LaconicReviewCore``

The provider-neutral core of laconic-review: review-domain types plus the single GitLab seam.

## Overview

`LaconicReviewCore` is the contract the review skill conforms to. Its public types — and the
GitLab calls in ``GitLabConnection`` — are the *interaction standard*; the skill reads this
catalog's symbol graph to learn what to emit and self-heals when it changes. Keep the doc
comments here accurate: they are the spec, not decoration.

The split is deliberate: review intelligence and the report format are neutral, and **only**
``GitLabConnection`` knows GitLab. Swapping providers (a future GitHub) means a second
connection type, not a rewrite.

## Topics

### Connecting

- ``GitLabConfig``
- ``ProjectContext``
- ``GitLabConnection``
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
and `<!-- finding … -->` HTML comments. SHAs are never persisted — `publish` fetches `diff_refs`
fresh and the seam combines them with a ``Position`` to build GitLab's line anchor.

- ``ReportParser``
- ``ReviewReport``
- ``ReviewHeader``
- ``Finding``
- ``FindingScope``
- ``LineSide``
- ``Position``

### Publishing (idempotent)

`publish` posts each open, not-yet-published finding as a discussion (line-anchored via
``Position``, or general), recording the result in the ``PublishLedger`` so re-runs are safe.

- ``GitLabConnection/postDiscussion(iid:body:position:diffRefs:)``
- ``GitLabConnection/resolveThread(iid:discussionID:resolved:)``
- ``PostedDiscussion``
- ``PublishLedger``
- ``PublishedThread``
