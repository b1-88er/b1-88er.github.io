---
layout: post
title: My discoveries about Elixir processes
date: 2015-10-22
summary: How did I learn about Elixir processes that is worth sharing.
categories: elixir
---

### Books
Learning new language is always challenging, especially if you try to learn something completely different from most of the languages out there. Elixir is one of them, sure it looks like Ruby, but the actual power of it comes from BEAM - VM that powers Erlang programs. The basic unit of Erlang concurrency model is a process. You can learn a lot about them here and there. The thing is, books cover them in a happy path manner. It means, that if copy-paste example from book it will run fine and everyone should be happy right? Well, not exactly. Experimenting with examples is always the most valuable thing that you can do (at least in my case), so I tried, this is what I came up with.

### Very basic spawn
The easiest way to spawn process in BEAM is to do it from shell.

{% highlight elixir %}
iex(1)> spawn(fn -> IO.puts "hello from process" end)
hello from process
#PID<0.61.0>
{% endhighlight %}

Every resource about Elixir will have such an example. Spawn/1 (there is `spawn/3`) runs functions in a fresh process and returns its identifier. Cool, but my questions were:

> Q: Is this PID is a completely random number?

> A: Not entirely, but you have no control over process id number. I found good [stackoverlow answer to that one](http://stackoverflow.com/questions/243363/can-someone-explain-the-structure-of-a-pid-in-erlang?rq=1)

> Q: Can this function take any argument?

> A: No, no arguments if you run process like that. You can do it in spawn/3

> Q: Is it a async operation, will the "spawner" wait for this process to finish?

> A: Lets check:

{% highlight elixir %}
iex(8)> spawn(fn ->
...(8)> IO.puts "hello from process"
...(8)> :timer.sleep(5000) # miliseconds
...(8)> end)
hello from process
#PID<0.75.0>
{% endhighlight %}

Shell will be available immediately, so the answer is "NO" - spawn won't wait for this process to finish.


> Q: So is this process even alive?

> A: Lets check:


{% highlight elixir %}
iex(9)> pid = spawn(fn -> IO.puts "hello from process" end)
hello from process
#PID<0.77.0>
iex(10)> Process.alive? pid
false
{% endhighlight %}

So process is dead after doing its job. So the answer is: NO - this process is dead.

### Process inside a module
I mentioned `spawn/3`. If you don't know what given function does, just type `h(function/number_arguments)` and you will see something like this:

{% highlight elixir %}
iex(11)> h(spawn/3)
Spawns the given module and function passing the given args and returns its
pid.

Check the modules Process and Node for other functions to handle processes,
including spawning functions in nodes.

Inlined by the compiler.

Examples

┃ spawn(SomeModule, :function, [1, 2, 3])
{% endhighlight %}


So this is straight forward. It is worth mentioning that the second argument must be an atom. And the third argument is a list of arguments, so if you want to pass a single list as an argument you need to pass `[[:items, :of, :a, :passed, :list]]`.

### Ping-pong game table

We can demonstrate some elixir processes properties during a simple exercise. Lets design a ping-pong table where each side "ping" and "pong" are going to be separate process exchanging messages. It will look like this:

```
+--------------+                                 
|              |                                 
|     iex      |                                 
|              |                                 
+------+-------+                                 
       |                                         
       |:ping                                    
       |                                         
+------v-------+     :pong       +--------------+
|              +----------------->              |
| ping process |                 | pong process |
|              <-----------------+              |
+--------------+     :ping       +--------------+
```


Lets define a module that spawns processes and starts interaction with them. We are going to solve this by incrementally adding code and asking bunch of noobie questions to learn as much as we can. Lets start with a basic process and a start function, we are trying to solve: *"iex" :pinging ping process*

{% highlight elixir %}
defmodule Table do
  def ping do
    receive do
      :ping -> IO.puts('received ping')
    end
  end

  def start do
    spawn(__MODULE__, :ping, [])
  end
end
{% endhighlight %}


Function *start* spawns a ping process and returns its PID. Remember, when spawning a process in module the second argument must be an __atom__ otherwise you can get unexpected result quite hard to debug later. In our case, if we call `spawn(__MODULE__, ping, [])`, we would not spawn a process but call a ping function instead, which would block forever at receive statement. Fortunately we have correct implementation so we can try it:

{% highlight elixir %}
iex(1)> ping = Table.start
#PID<0.67.0>
iex(2)> Process.alive? ping
true
{% endhighlight %}

#### Tail-recursion, keeping process alive.

It looks good, PID is alive and well. Now it is time send a message to it, lets do it a few times and realize that after sending a first message our process is dead.
{% highlight elixir %}
iex(3)> send ping, :ping
received ping
:ping
iex(4)> send ping, :ping
:ping
iex(5)> Process.alive? ping
false
{% endhighlight %}

Process is dead because after receiving message is continues executing a function, in our case it is the *end* statement. Adding recursive call to itself would keep ping process alive.
{% highlight elixir %}
def ping do
  receive do  # 1. block here and wait for a message
    :ping -> IO.puts('received ping')
  end
  ping # 2. Call itself
end
{% endhighlight %}
It should work like this:

1. `spawn(__MODULE__, :ping, [])` - spawn ping function in separate process
+ Block at receive statement __(#1)__
+ Receive message and call itself __(#2)__
+ Block at receive statement and wait for messages __(#1)__ and so on.

{% highlight elixir %}
iex(7)> p = Table.start
#PID<0.78.0>
iex(8)> send p, :ping
received ping
:ping
iex(9)> send p, :ping
received ping
:ping
iex(10)> send p, :ping
received ping
:ping
iex(11)> Process.alive? p
true
{% endhighlight %}

> Q: This is a recursion, am I going to overflow stack in this way?

> A: No, elixir uses something called tail-recursion - it basically means that elixir will convert this recursive call to a loop during compilation. We can actually check if that's true.

We are going to use a tool called [observer](http://www.erlang.org/doc/man/observer.html).
{% highlight elixir %}
iex(5)> :observer.start
{% endhighlight %}
You should see window like this one.

![Erlang VM observer]({{ site.baseurl }}/images/erlang_vm_observer.png)

Go ahead, click around and explore. Especially applications tab is interesting. You can peek and check process trees. Now we are ready to benchmark our ping process, we are going to call it 100M times, just type following line and go right to observer window.
{% highlight elixir %}
iex(3)> p = Table.start
#PID<0.1569.0>
iex(4)> 1..100000000 |> Stream.map(fn _ -> send p, {self(), :ping} end) |> Enum.count
100000000
{% endhighlight %}

Go to *Load Charts*. Memory usage will increase at first, but it at some point it should be constant during our micro benchmark execution.
![Erlang VM observer]({{ site.baseurl }}/images/erlang_vm_observer_memory_usage.png)


You can also check in *processes* tab how our ping process is doing.
![Erlang VM observer]({{ site.baseurl }}/images/erlang_vm_observer_ping_process.png)


#### self() or "who am I"?

Before we begin implementating interaction between processes, lets try something new.

{% highlight elixir %}
iex(1)> self()

#PID<0.57.0>

iex(2)> h(self)

                                   def self()

Returns the pid (process identifier) of the calling process.

Allowed in guard clauses. Inlined by the compiler.
{% endhighlight %}

What did we learn here? First of all, code that we execute in a REPL is executed in a process as well. We also know how get a PID of process that we are currently in. Lets dig a bit deeper now by sending messages to self() process in REPL, make sure you have running observer first.

{% highlight elixir %}
iex(16)> :observer.start
:ok
iex(17)> self()
#PID<0.57.0>
iex(18)> send self(), "HELLO"
"HELLO"
iex(19)> send self(), "HELLO"
"HELLO"
iex(20)> send self(), "HELLO"
"HELLO"
iex(21)> send self(), "HELLO"
"HELLO"
{% endhighlight %}

We sent messages, but did they go? Lets check process tab in observer, sort the table by *MsgQ* which says how many messages are waiting in queue to given process. We sent 4 messages so are looking for a process with MsgQ equals 4.

![self() queue process]({{ site.baseurl }}/images/erlang_vm_observer_self_queue.png)

You can see that we sent 4 messages to self(), and queue is 4 items long. Remember, it is not permanent queue, once you kill the VM messages will be lost. Now it is time receive these messages, for this we are going to use *flush/0* function. You can even peek what items are in queue, just double-click on a process and go to *messages* tab.

![queue msgs list]({{ site.baseurl }}/images/erlang_vm_observer_process_queue_peek.png)

But how to consume messages sent to shell process?

{% highlight elixir %}
iex(4)> h(flush)

                                  def flush()

Flushes all messages sent to the shell and prints them out.
iex(23)> flush
"HELLO"
"HELLO"
"HELLO"
"HELLO"
:ok
{% endhighlight %}

No that we know a bit more about self function, lets try it in our ping-pong table!

#### Sending messages back and forth between processes

By far we were receiving messages in a process, but to we didn't send any messages back yet. *IO.puts* is a useful function, but we want our process to communicate. Lets try example below.

{% highlight elixir %}
defmodule Table do
  def ping do
    receive do
      {from, :ping} ->  #1
        IO.puts 'ping process reached, going to respond with :pong'
        send from, {self(), :pong} #2
    end
    ping
  end

  def start do
    spawn(__MODULE__, :ping, [])
  end
end
{% endhighlight %}

We changed the way what we receive in *#1*, instead expecting a *:ping* atom we wait for a tuple *{from, :ping}*. It means, that we will know not only that someone sends us :ping, but also who is sending it. In *#2* we respond in the same manner, we send a tuple *back to the sender* of the :ping atom, but also with the information who is sending it - the ping process - self(). Now, since we know how self() works, we can test our ping process from a shell.

{% highlight elixir %}
iex(11)> p = Table.start
#PID<0.80.0>  #1
iex(12)> send(p, {self(), :ping}) #2
ping process reached, going to respond with :pong
{#PID<0.57.0>, :ping} #3
iex(13)> flush
{#PID<0.80.0>, :pong}  #4
:ok
{% endhighlight %}

First we spawn ping process in start function *#1*, it returns a PID 0.80.0 of the ping process. Then we send tuple of *{self, :ping}* to ping process (*#2*), at *#3* we can see what has been sent. The *#4* is the message sent back from ping process. We are very close to the finish now. All we have to do, is to create similar function to ping process called *pong*. Example bellow does the job.

{% highlight elixir %}
defmodule Table do
  def ping do
    receive do
      {from, :ping} ->
        IO.puts 'ping process reached, going to respond with :pong'
        :timer.sleep(1000)
        send from, {self(), :pong}
    end
    ping
  end

  def pong do #1
    receive do
      {from, :pong} -> #2
        IO.puts 'pong process reached, going to respond with :ping'
        :timer.sleep(1000) #4
        send from, {self(), :ping} #3
    end
    pong
  end

  def start do
    ping_pid = spawn __MODULE__, :ping, []
    pong_pid = spawn __MODULE__, :pong, [] #5
    {ping_pid, pong_pid}
  end
end
{% endhighlight %}


The pong function (*#1*) is very similar to the ping one. The main difference is that we expect *:pong* instead of :ping atom (*#2*) and we respond with *:ping* - not :pong (*#3*). I also put a *:timer.sleep(1000)* to hold execution for a 1 second (*#4*), just to avoid flooding ourselves with messages. If you want to call some code from standard Erlang library, just use it like *:module_name.function*. We also had to add *pong_pid = spawn __MODULE__, :pong, []* in *#5* to actually create a pong process, lets play with what we have.

{% highlight elixir %}
iex(12)> {ping, pong} = Table.start #1
iex(13)> send ping, {pong, :ping} #2
ping process reached, going to respond with :pong
{#PID<0.13059.0>, :ping}
pong process reached, going to respond with :ping
ping process reached, going to respond with :pong
pong process reached, going to respond with :ping
ping process reached, going to respond with :pong
pong process reached, going to respond with :ping
ping process reached, going to respond with :pong
pong process reached, going to respond with :ping
ping process reached, going to respond with :pong
{% endhighlight %}

At *#1* we pattern match what *Table.start* function returns - *{ping, pong}* PIDs. Now it might get a bit confusing, we send *{pong, :ping}* to *ping* - why didn't we send *{self, :ping}* like before? It is because we want ping process to think that pong is sending the message, so we to have lie to ping process at first, remember that graph?


```
+--------------+                                 
|              |                                 
|     iex      |                                 
|              |                                 
+------+-------+                                 
       |                                         
       |{pong_pid, :ping} we do it first because in {from, :ping} - from must be pong PID!
       |                                         
+------v-------+  {self, :pong}  +--------------+
|              +----------------->              |
| ping process |                 | pong process |
|              <-----------------+              |
+--------------+  {self, :pong}  +--------------+
```


Eureka! We finish the PingPong table exercise!

> Q: But how to stop this "printing pong process reached, going to respond with :ping" ?

> A: Just kill one of the process - ping or pong.


It is easy, first check: [http://elixir-lang.org/docs/v1.0/elixir/Process.html#exit/2](http://elixir-lang.org/docs/v1.0/elixir/Process.html#exit/2)

{% highlight elixir %}
iex(14)> Process.exit(ping, :kill)
{% endhighlight %}

So, ping is dead, but pong should be still alive, lets check it
{% highlight elixir %}
iex(16)> Process.alive? pong
true
iex(17)> Process.alive? ping
false
{% endhighlight %}


That is it, hope you learned something new!
