using WeChatMulti.Core;
using Xunit;

namespace WeChatMulti.Core.Tests;

public class InstanceOrderingTests
{
    [Fact]
    public void MoveBeforeTarget()
    {
        Assert.Equal(new[] { 3, 1, 2 }, InstanceOrdering.Reorder(new[] { 1, 2, 3 }, 3, 1));
        Assert.Equal(new[] { 2, 1, 3 }, InstanceOrdering.Reorder(new[] { 1, 2, 3 }, 1, 3));
    }

    [Fact]
    public void MoveToEndWhenTargetNull()
        => Assert.Equal(new[] { 2, 3, 1 }, InstanceOrdering.Reorder(new[] { 1, 2, 3 }, 1, null));

    [Fact]
    public void MoveToEndWhenTargetMissing()
        => Assert.Equal(new[] { 1, 3, 2 }, InstanceOrdering.Reorder(new[] { 1, 2, 3 }, 2, 99));

    [Fact]
    public void NoOpWhenMovingOntoItself()
        => Assert.Equal(new[] { 1, 2, 3 }, InstanceOrdering.Reorder(new[] { 1, 2, 3 }, 2, 2));

    [Fact]
    public void MovingIdNotInList()
        => Assert.Equal(new[] { 1, 5, 2, 3 }, InstanceOrdering.Reorder(new[] { 1, 2, 3 }, 5, 2));

    [Fact]
    public void ReorderDoesNotDuplicate()
    {
        var result = InstanceOrdering.Reorder(new[] { 0, 1, 2 }, 0, 2);
        Assert.Equal(new[] { 1, 0, 2 }, result);
        Assert.Equal(result.Count, result.Distinct().Count());
    }

    [Fact]
    public void ResolveHonorsSavedOrderThenAppendsNew()
        => Assert.Equal(new[] { 2, 1, 0, 3 },
            InstanceOrdering.Resolve(new[] { 2, 1 }, new[] { 0, 1, 2, 3 }));

    [Fact]
    public void ResolveFiltersStaleEntries()
        => Assert.Equal(new[] { 2, 1 },
            InstanceOrdering.Resolve(new[] { 9, 2, 1 }, new[] { 1, 2 }));

    [Fact]
    public void ResolveEmptyOrderIsNaturalSequence()
        => Assert.Equal(new[] { 0, 1, 2 },
            InstanceOrdering.Resolve(Array.Empty<int>(), new[] { 0, 1, 2 }));

    [Fact]
    public void ResolveDedupesDuplicateOrderEntries()
        => Assert.Equal(new[] { 1, 2, 3 },
            InstanceOrdering.Resolve(new[] { 1, 1, 2 }, new[] { 1, 2, 3 }));

    [Fact]
    public void ResolveEmptyAvailable()
        => Assert.Empty(InstanceOrdering.Resolve(new[] { 1, 2 }, Array.Empty<int>()));
}
