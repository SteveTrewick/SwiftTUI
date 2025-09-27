
import Foundation

/*
  ok, lets do a ring thing
*/


public struct CircularBuffer<T>  {

    /*
      so one problem with doing this swifty and not doing horrible unsafe pointer
      buffers is that we can't have a fixed size array which makes it a bit of a twat to
      do O(1) insertions with a straight face. Probably doesn't matter here, but still,
      sometimes even a grizzled old hack likes a bit of probably pointless micro
      optimisation so we'll fill capacity nils to prevent doing bounds checks and appends
      and also since it will avoid mallocs. probably.
    */

    var capacity : Int
    var filled   : Int
    var elements : [T?]
    var head     : Int
    var tail     : Int

    // NB that the actual capacity of a circular buffer is in fact (capacity - 1)

    public init(capacity: Int) {
      self.capacity = capacity
      self.elements = [T?](repeating: nil, count: capacity)
      self.head     = 0
      self.tail     = 0
      self.filled   = 0
    }

    public mutating func put(_ element: T) {
      
      elements[head] = element
      head = (head + 1) % capacity
      
      if head == tail {              // buffer is full and now overwriting its own ass
        tail = (tail + 1) % capacity // if we cared about that, we should bounce this
      }                              // but I actually want it to discard old values...
      
      filled = min((filled + 1),  capacity)
    }

    // ...so instead we'll put a check, for completeness sake.
    public var isFull : Bool { return head == tail }



    // traditionally, we are also supposed to be able to read off the end.
    // probably not going to, but hey, completey.

    public mutating func get() -> T {
      defer {
        tail = (tail + 1) % capacity
      }
      return elements[tail]! // NB this here is fatal, your pointers are wrong.
    }

    }

    // extras
    extension CircularBuffer {

    // now usually, we wouldn't subscript this, because you are supposed to read from
    // the end of the buffer but we want to read the whole buffer or sections of it, so...

    // you will need to pay attention to the actual pointers VERY CAREFULLY
    // if you want the result of this to make sense, SEE BELOW

    public subscript(_ index: Int) -> T? {
      elements[index]
    }

}


// Now, we have a circular buffer, with two pointers, like a clock, so when
// we do arithmetic based on either of those we need to use modular arithmetic.
// But as many have found to their cost, the good old % operator is NOT actually
// "the mod operator" it is THE REMAINDER operator which is fine if you happen
// to be trying to navigate clockwise or only use positive increments, but it
// doesn't work with negatives, so ...

// I don't think this really needs to be an infix operator, TBH, but eh, it can be
// so why not?  I mean, this whole program is already on many levels of not needing
// to exist either in whole or part, so, eh, lets do it.

infix operator %%

extension BinaryInteger {
    static func %% (_ lhs: Self, _ rhs: Self) -> Self {
       let mod = lhs % rhs
       return mod >= 0 ? mod : mod + rhs
    }
}




/*
  OK, now we'll see why it wasn't really all that necessary to have the ring
  be optimal (or exist), because we're going to do this to it.
 
  basically, every time we get characters, we feed them in here, break up the lines,
  stick the whole ones in teh buffer and hold on to the last incomplete one, if any.
 
  Though, now I come to think of it, on scroll, we could actually just stuff the
  last line in the buffer without a \n couldn't we? arse.
 
  Aaaaanyhoo.
*/

public struct LineBuffer {
  
  var buffer      : CircularBuffer<String>
  var currentline : String
  let breakchar   : Character
  var offset      : Int
  
  
  public init ( capacity: Int, breakchar: Character ) {
    self.buffer      = CircularBuffer<String>(capacity: capacity)
    self.currentline = ""
    self.breakchar   = breakchar
    self.offset      = 0
  }
  
  
  public mutating func push ( chars: String ) {
    
    for char in chars {
      
      currentline.append ( char )
      
      if char == breakchar {
          buffer.put (currentline)
          currentline = ""
      }
    }
  }
  
  // we need to be checking the spans here, or in the calling code
  public mutating func scrollUp (span: Int, _ count : Int = 1) {
    let maxoffset = (buffer.filled + 1) - span
    offset = min(offset + count, maxoffset)
  }
  public mutating func scrollDown ( _ count: Int = 1) {
    offset = max(0, offset - count)
  }
  
  
  public mutating func fetch (span: Int) -> [String] {
    
    var lines : [String] = []

    let spantop = (buffer.head - offset - (span - 1))  %%  buffer.capacity
    
    log("span \(span)")
    log("spantop \(spantop)")
    
    for i in 0..<(span) {
      
      let pos = (spantop + i) %% buffer.capacity
      
      if pos == buffer.head { lines.append( currentline )   }
      else                  { lines.append( String(buffer[ pos ]!.dropLast())) }  // still got an explodey nil
    }                       // NB the last char on all non curremt lines == newline
                            //    which will scroll when we hit the bottom, bad.
    return lines
  }
}
/*
 frankly I'm not sold on that solution long term, but for now,
 it will do, we certainly know that whatever is at the end of the line
 is what we used to break the lines up, so it will probably work,
 right up until it doesnt, and we will deal with it then.

 well, it doesn't now. bugger, scroll when we arent at the bottom is broken
 need to fix that. OK, span == 24, should be the cursor line.
 
*/
