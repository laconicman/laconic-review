# ``FlatReviewCore``

The provider-neutral core of laconic-review: review-domain types plus the single GitLab seam.

## Overview

`FlatReviewCore` is the contract the review skill conforms to. Its public types — and the
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
