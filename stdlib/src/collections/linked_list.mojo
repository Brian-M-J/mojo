# ===----------------------------------------------------------------------=== #
# Copyright (c) 2024, Modular Inc. All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions:
# https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #

from memory import UnsafePointer, Pointer
from sys.info import alignof
from collections import Optional


@value
struct _LinkedListNode[T: CollectionElement]():
    alias PointerT = UnsafePointer[Self]

    var data: T
    var next: Self.PointerT
    var prev: Self.PointerT

    fn __init__(out self, owned data: T):
        self.data = data
        self.next = Self.PointerT()
        self.prev = Self.PointerT()


struct LinkedList[T: CollectionElement](
    CollectionElement, CollectionElementNew, Sized, Boolable
):
    """The `LinkedList` type is a dynamically-allocated doubly linked list.

    It supports pushing to the front and back in O(1).

    Parameters:
        T: The type of the elements.
    """

    alias NodeT = _LinkedListNode[T]
    alias PointerT = UnsafePointer[Self.NodeT]

    var _length: Int
    var _head: Self.PointerT
    var _tail: Self.PointerT

    fn __init__(out self):
        """Default construct an empty list."""
        self._length = 0
        self._head = Self.PointerT()
        self._tail = Self.PointerT()

    fn __init__(out self, owned *elems: T):
        """
        Construct a list with the provided elements.

        Args:
            elems: The elements to add to the list.
        """
        self = Self(elements=elems^)

    fn __init__(out self, *, owned elements: VariadicListMem[T, _]):
        """
        Construct a list from a `VariadicListMem`.

        Args:
            elements: The elements to add to the list.
        """
        self = Self()

        var length = len(elements)

        for i in range(length):
            var src = UnsafePointer.address_of(elements[i])
            var node = Self.PointerT.alloc(1)
            var dst = UnsafePointer.address_of(node[].data)
            src.move_pointee_into(dst)
            node[].next = Self.PointerT()
            node[].prev = self._tail
            if not self._tail:
                self._head = node
                self._tail = node
            else:
                self._tail[].next = node
                self._tail = node

        # Do not destroy the elements when their backing storage goes away.
        __mlir_op.`lit.ownership.mark_destroyed`(
            __get_mvalue_as_litref(elements)
        )

        self._length = length

    fn push_back(mut self, owned elem: T):
        """
        Append the provided element to the end of the list.
        O(1) time complexity.

        Args:
            elem: The element to append to the list.
        """
        var node = Self.PointerT.alloc(1)
        var data = UnsafePointer.address_of(node[].data)
        data.init_pointee_move(elem^)
        node[].prev = self._tail
        if self._tail:
            self._tail[].next = node
        self._tail = node
        self._length += 1
        if not self._head:
            self._head = node

    fn append(mut self, owned elem: T):
        """
        Append the provided element to the end of the list.
        O(1) time complexity. Alias for list compatibility.

        Args:
            elem: The element to append to the list.
        """
        self.push_back(elem^)

    fn push_front(mut self, owned elem: T):
        """
        Append the provided element to the front of the list.
        O(1) time complexity.

        Args:
            elem: The element to prepend to the list.
        """
        var node = Self.PointerT.alloc(1)
        node.init_pointee_move(Self.NodeT(elem^))
        node[].next = self._head
        if self._head:
            self._head[].prev = node
        self._head = node
        self._length += 1
        if not self._tail:
            self._tail = node

    fn insert(mut self, owned idx: Int, owned elem: T) raises:
        """
        Insert an element `elem` into the list at index `idx`.

        Args:
            idx: The index to insert `elem` at.
            elem: The item to insert into the list.
        """
        var i = max(0, index(idx) if idx >= 0 else index(idx) + len(self))

        if i == 0:
            var node = Self.PointerT.alloc(1)
            node.init_pointee_move(Self.NodeT(elem^))

            if self._head:
                node[].next = self._head
                self._head[].prev = node

            self._head = node

            if not self._tail:
                self._tail = node

            self._length += 1
            return

        i -= 1

        var current = self._get_nth(i)
        if current:
            var next = current[].next
            var node = Self.PointerT.alloc(1)
            if not node:
                raise "OOM"
            var data = UnsafePointer.address_of(node[].data)
            data[] = elem^
            node[].next = next
            node[].prev = current
            if next:
                next[].prev = node
            current[].next = node
            if node[].next == Self.PointerT():
                self._tail = node
            if node[].prev == Self.PointerT():
                self._head = node
            self._length += 1
        else:
            raise "index out of bounds"

    fn head(ref self) -> Optional[Pointer[T, __origin_of(self)]]:
        """
        Gets a reference to the head of the list if one exists.
        O(1) time complexity.

        Returns:
            An reference to the head if one is present.
        """
        if self._head:
            return Optional[Pointer[T, __origin_of(self)]](
                Pointer.address_of(self._head[].data)
            )
        else:
            return Optional[Pointer[T, __origin_of(self)]]()

    fn tail(ref self) -> Optional[Pointer[T, __origin_of(self)]]:
        """
        Gets a reference to the tail of the list if one exists.
        O(1) time complexity.


        Returns:
            An reference to the tail if one is present.
        """
        if self._tail:
            return Optional[Pointer[T, __origin_of(self)]](
                Pointer.address_of(self._tail[].data)
            )
        else:
            return Optional[Pointer[T, __origin_of(self)]]()

    fn _get_nth(ref self, read idx: Int) -> Self.PointerT:
        debug_assert(-len(self) <= idx < len(self), "index out of range")

        if Int(idx) >= 0:
            if self._length <= idx:
                return Self.PointerT()

            var cursor = UInt(idx)
            var current = self._head

            while cursor > 0 and current:
                current = current[].next
                cursor -= 1

            if cursor > 0:
                return Self.PointerT()
            else:
                return current
        else:
            # print(index(idx))
            var cursor = (idx * -1) - 1
            # print(cursor)
            var current = self._tail

            while cursor > 0 and current:
                # print("loop")
                current = current[].prev
                cursor -= 1

            if cursor > 0:
                return Self.PointerT()
            else:
                # print(current)
                # var c = self._head
                # for i in range(len(self)):
                #     print(c)
                #     c = c[].next
                return current

    fn __getitem__[I: Indexer](ref self, read idx: I) raises -> ref [self] T:
        """
        Returns a reference the indicated element if it exists.
        O(len(self)) time complexity.

        Parameters:
            I: The type of indexer to use.

        Args:
            idx: The index of the element to retrieve. Negative numbers are converted into an offset from the tail.

        Returns:
            A `Pointer` to the element at the provided index, if it exists.
        """
        var current = self._get_nth(Int(idx))

        if not current:
            raise "index out of bounds"
        else:
            return UnsafePointer[T].address_of(current[].data)[]

    fn __setitem__[I: Indexer](ref self, read idx: I, owned value: T) raises:
        """
        Sets the item at index `idx` to `value`, destroying the current value.
        O(len(self)) time complexity.

        Parameters:
            I: The type of indexer to use.

        Args:
            idx: The index of the element to retrieve. Negative numbers are converted into an offset from the tail.
            value: The value to emplace into the list.

        Raises:
            Raises if given an out of bounds index.
        """
        var current = self._get_nth(Int(idx))

        if not current:
            raise "index out of bounds"

        var data = UnsafePointer.address_of(current[].data)
        data.init_pointee_move(value^)

    fn pop(mut self) -> Optional[T]:
        """
        Remove the last element of the list.

        Returns:
            The element, if it was found.
        """
        return self.pop(len(self) - 1)

    fn pop[I: Indexer](mut self, owned i: I) -> Optional[T]:
        """
        Remove the ith element of the list, counting from the tail if
        given a negative index.

        Parameters:
            I: The type of index to use.

        Args:
            i: The index of the element to get.

        Returns:
            The element, if it was found.
        """
        var current = self._get_nth(Int(i))

        if not current:
            return Optional[T]()
        else:
            var node = current[]
            if node.prev:
                node.prev[].next = node.next
            else:
                self._head = node.next
            if node.next:
                node.next[].prev = node.prev
            else:
                self._tail = node.prev

            var data = node.data^

            # Aside from T, destructor is trivial
            __mlir_op.`lit.ownership.mark_destroyed`(
                __get_mvalue_as_litref(node)
            )
            current.free()
            self._length -= 1
            return Optional[T](data)

    fn clear(mut self):
        """Removes all elements from the list."""
        var current = self._head
        while current:
            var old = current
            current = current[].next
            old.destroy_pointee()
            old.free()

        self._head = Self.PointerT()
        self._tail = Self.PointerT()
        self._length = 0

    fn __len__(read self) -> Int:
        """
        Returns the number of elements in the list.

        Returns:
            The length of the list.
        """
        return self._length

    fn empty(self) -> Bool:
        """
        Whether the list is empty.

        Returns:
            Whether the list is empty or not.
        """
        return not self._head

    fn __bool__(self) -> Bool:
        """
        Casts self to `Bool` based on whether the list is empty or not.

        Returns:
            Whether the list is empty or not.
        """
        return not self.empty()

    fn __copyinit__(out self, read existing: Self):
        """Creates a deepcopy of the given list.

        Args:
            existing: The list to copy.
        """
        self = Self()
        var n = existing._head
        while n:
            self.push_back(n[].data)
            n = n[].next

    fn copy(read self) -> Self:
        """
        Creates a deepcopy of this list and return it.

        Returns:
            A copy of this list.
        """
        return Self.__copyinit__(self)

    fn __moveinit__(out self, owned existing: Self):
        """Move data of an existing list into a new one.

        Args:
            existing: The existing list.
        """
        self._length = existing._length
        self._head = existing._head
        self._tail = existing._tail

    fn __del__(owned self):
        """Destroy all elements in the list and free its memory."""

        var current = self._head
        while current:
            var prev = current
            current = current[].next
            prev.destroy_pointee()

    fn reverse(mut self):
        """Reverses the list in-place."""
        var current = self._head

        while current:
            current[].next, current[].prev = current[].prev, current[].next
            current = current[].prev

        self._head, self._tail = self._tail, self._head

    fn __reversed__(self) -> Self:
        """
        Create a reversed copy of the list.

        Returns:
            A reversed copy of the list.
        """
        var rev = Self()

        var current = self._tail
        while current:
            rev.push_back(current[].data)
            current = current[].prev

        return rev

    fn extend(mut self, owned other: Self):
        """
        Extends the list with another.
        O(1) time complexity.

        Args:
            other: The list to append to this one.
        """
        if self._tail:
            self._tail[].next = other._head
            if other._head:
                other._head[].prev = self._tail
            if other._tail:
                self._tail = other._tail

            self._length += other._length
        else:
            self._head = other._head
            self._tail = other._tail
            self._length = other._length

        other._head = Self.PointerT()
        other._tail = Self.PointerT()

    fn count[
        T: EqualityComparableCollectionElement
    ](self: LinkedList[T], read elem: T) -> UInt:
        """
        Count the occurrences of `elem` in the list.

        Parameters:
            T: The list element type, used to conditionally enable the function.

        Args:
            elem: The element to search for.

        Returns:
            The number of occurrences of `elem` in the list.
        """
        var current = self._head
        var count = 0
        while current:
            if current[].data == elem:
                count += 1

            current = current[].next

        return count

    fn __contains__[
        T: EqualityComparableCollectionElement, //
    ](self: LinkedList[T], value: T) -> Bool:
        """
        Checks if the list contains `value`.

        Parameters:
            T: The list element type, used to conditionally enable the function.

        Args:
            value: The value to search for in the list.

        Returns:
            Whether the list contains `value`.
        """
        var current = self._head
        while current:
            if current[].data == value:
                return True
            current = current[].next

        return False

    fn __eq__[
        T: EqualityComparableCollectionElement, //
    ](read self: LinkedList[T], read other: LinkedList[T]) -> Bool:
        """
        Checks if the two lists are equal.

        Parameters:
            T: The list element type, used to conditionally enable the function.

        Args:
            other: The list to compare to.

        Returns:
            Whether the lists are equal.
        """
        if self._length != other._length:
            return False

        var self_cursor = self._head
        var other_cursor = other._head

        while self_cursor:
            if self_cursor[].data != other_cursor[].data:
                return False

            self_cursor = self_cursor[].next
            other_cursor = other_cursor[].next

        return True

    fn __ne__[
        T: EqualityComparableCollectionElement, //
    ](self: LinkedList[T], other: LinkedList[T]) -> Bool:
        """
        Checks if the two lists are not equal.

        Parameters:
            T: The list element type, used to conditionally enable the function.

        Args:
            other: The list to compare to.

        Returns:
            Whether the lists are not equal.
        """
        return not (self == other)

    @no_inline
    fn __str__[
        U: RepresentableCollectionElement, //
    ](self: LinkedList[U]) raises -> String:
        """Returns a string representation of a `List`.

        Note that since we can't condition methods on a trait yet,
        the way to call this method is a bit special. Here is an example below:

        ```mojo
        var my_list = LinkedList[Int](1, 2, 3)
        print(my_list.__str__())
        ```

        When the compiler supports conditional methods, then a simple `str(my_list)` will
        be enough.

        The elements' type must implement the `__repr__()` method for this to work.

        Parameters:
            U: The type of the elements in the list. Must implement the
              traits `Representable` and `CollectionElement`.

        Returns:
            A string representation of the list.
        """
        var output = String()
        self.write_to(output)
        return output^

    @no_inline
    fn write_to[
        W: Writer, U: RepresentableCollectionElement, //
    ](self: LinkedList[U], mut writer: W) raises:
        """Write `my_list.__str__()` to a `Writer`.

        Parameters:
            W: A type conforming to the Writable trait.
            U: The type of the List elements. Must have the trait `RepresentableCollectionElement`.

        Args:
            writer: The object to write to.
        """
        writer.write("[")
        for i in range(len(self)):
            writer.write(repr(self[i]))
            if i < len(self) - 1:
                writer.write(", ")
        writer.write("]")

    @no_inline
    fn __repr__[
        U: RepresentableCollectionElement, //
    ](self: LinkedList[U]) raises -> String:
        """Returns a string representation of a `List`.

        Note that since we can't condition methods on a trait yet,
        the way to call this method is a bit special. Here is an example below:

        ```mojo
        var my_list = LinkedList[Int](1, 2, 3)
        print(my_list.__repr__())
        ```

        When the compiler supports conditional methods, then a simple `repr(my_list)` will
        be enough.

        The elements' type must implement the `__repr__()` for this to work.

        Parameters:
            U: The type of the elements in the list. Must implement the
              traits `Representable` and `CollectionElement`.

        Returns:
            A string representation of the list.
        """
        return self.__str__()
