---
date: "2015-11-12T00:00:00Z"
summary: You are familiar with basic concept of Elixir/Erlang processes and you want
  to take a step further.
title: Linking Elixir processes together
---

## Intro

If you actually don't know much about Elixir processes but you already learned something about Elixir checkout [my post about processes]({% post_url 2015-10-22-elixir-pingpong-table %}) and come back afterwords. I assume that you know how **spawn/1** and **spawn/3** work and you know basic concepts around process communication.


## Connecting processes together.

It is very common that processes are somehow related to each other, we also know that they do not share state. Right now you should be asking: **"How to make sure that life of process depends on another?"**. Erlang provides mechanism called linking. In Elixir we can use it by calling **spawn_link**. Let's check what docs have to say about that function.

```elixir
def spawn_link(fun)

Spawns the given function, links it to the current process and returns its pid.

Check the Process and Node modules for other functions to handle processes,
including spawning functions in nodes.

Inlined by the compiler.

Examples

┃ current = self()
┃ child   = spawn_link(fn -> send current, {self(), 1 + 2} end)
┃
┃ receive do
┃   {^child, 3} -> IO.puts "Received 3 back"
┃ end
```

In my opinion, that description is quite vage, so let's put to the test.

```elixir
iex(4)> child   = spawn_link(fn -> send current, {self(), 1 + 2} end)
#PID<0.65.0>
iex(5)> receive do
...(5)>   {^child, 3} -> IO.puts "Received 3 back"
...(5)> end
Received 3 back
:ok
iex(6)>
```

We received 3, which is OK, but

> Q: what if we call spawn instead of spawn_link?

```elixir
iex(1)> current = self()
#PID<0.57.0>
iex(2)> child   = spawn(fn -> send current, {self(), 1 + 2} end)
#PID<0.60.0>
iex(3)> receive do
...(3)>   {^child, 3} -> IO.puts "Received 3 back"
...(3)> end
Received 3 back
:ok
```

> Q: The result is exactly the same, so what is the exact purpose of **spawn_link** then?

> A: The answer is: "Error handling"

Or to be more specific: "spawn_link will notify linked process about abnormal exit reason for the dependent process". But before going any deeper we need to really understand what actually happens when process finishes its work.

## When process ends

![oracle matrix meme](/images/meme_oracle_happens_for_a_reason.jpg)
When a process finishes its work, it exits. It is a different mechanism than exceptions and with it we can detect when something wrong (or unexpected) happens. When process finishes its work it implicitly calls **exit(:normal)** to communicate with its parent that job has been done. Every other argument to exit/1 than **:normal** is treated as an error. You should also know that Elixir shell is a process as well, so you should be able to link to it as well.

```elixir
iex(1)> spawn_link(fn -> exit(:normal) end)
#PID<0.104.0>
iex(2)> spawn(fn -> exit(:normal) end)
#PID<0.106.0>
```

So far there are no changes between **spawn/1** and **spawn_link/1**, that is because we exit the process with **:normal** reason. But what would happen for other reasons?
```elixir
{iex(1)> spawn(fn -> exit(:oh_no_i_did_something_wrong) end)
#PID<0.114.0>
iex(2)> spawn_link(fn -> exit(:oh_no_i_did_something_wrong) end)
** (EXIT from #PID<0.112.0>) :oh_no_i_did_something_wrong

Interactive Elixir (1.1.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)>
```

BINGO! Our shell processes does not catch **:EXIT** message, so link propagates the exit reason further to the process that observers elixir shell. The "observer" catches the error and restarts the shell process. But how to actually handle exit messages from linked processes?

## Trapping exists

Now that we know how to track exits from linked processes, the question is:

> Q: How to actually react to failures of linked processes?

> A: trap_exit

Each process can be flagged, meaning you can customize its properties like minimal heap size, priority level, **trapping** and many more advanced things. [Erlang's documentation lists them all](http://www.erlang.org/doc/man/erlang.html#process_flag-2). The most interesting part is this:

> Setting trapping flag to true means that, exit signals arriving to a process are converted to **{'EXIT', from, reason}** messages, which can be received as ordinary messages. If trap_exit is set to false, the process exits if it receives an exit signal other than normal and the exit signal is propagated to its linked processes. Application processes should normally not trap exits.

So setting trapping flag is not a common thing, it is because OTP from Erlang provides special building blocks for managing failures of other processes - **supervisors**. I will describe them in the next blog post, but for the time being we will go against the wind which is what curious programmers like most. Let's start with trapping exists from linked processes by setting the proper flag.


```elixir
iex(2)> Process.flag(:trap_exit, true)
false
```

As it is said in the description, returned value is **false** which is a previous state of that flag. If you called it again it would return true. Now that we have trapping enabled let's link to the process which calculates 1 + 1 and finishes its work. We call flush afterwords to receive incoming messages to the shell process.

```elixir
iex(3)> spawn_link(fn -> 1 + 1 end)
#PID<0.145.0>
iex(4)> flush
{:EXIT, #PID<0.145.0>, :normal}
:ok
```

Spawned process sends us **{:EXIT, #PID<0.145.0>, :normal}**. This means that process finishes its work without any problems. Now, let's replicate that behavior more explicitly.

```elixir
iex(5)> spawn_link(fn -> exit(:normal) end)
#PID<0.164.0>
iex(6)> flush
{:EXIT, #PID<0.164.0>, :normal}
:ok
```

Now let's try to exit the process with a message different then normal.

```elixir
iex(7)> spawn_link(fn -> exit(:custom_reason) end)
#PID<0.167.0>
iex(8)> flush
{:EXIT, #PID<0.167.0>, :custom_reason}
:ok
```

Great, we intercept exit call and statement such as

```elixir
receive do
  {:EXIT, pid, reason} -> here we could react
end
```

gives us a way to react to processes exits. But what about exceptions? They cause processes to die too!

```elixir
iex(11)> spawn_link(fn -> raise "uuuuups!" end)
#PID<0.174.0>

22:28:14.246 [error] Process #PID<0.174.0> raised an exception
** (RuntimeError) uuuuups!
    :erlang.apply/2
iex(12)> flush
{:EXIT, #PID<0.174.0>,
 {\%RuntimeError{message: "uuuuups!"}, [{:erlang, :apply, 2, []}]}}
:ok
```

Great, exceptions are trapped as well. We could react to them during processes exists.


## Visualizing links

Now that we have some knowledge about links, i'll show a visualization of simple demo. LinksTest module creates a chain of linked processes and then tracks their exits.

Here is the code:
```elixir
defmodule LinksTest do
  def chain 0 do
    IO.puts "chain called with 0, wating 2000 ms before exit"
    :timer.sleep(2000)
    exit(:chain_breaks_here)
  end

  def chain n do
    Process.flag(:trap_exit, true)
    IO.puts "chain called with #{n}"
    :timer.sleep(1000)
    spawn_link(__MODULE__, :chain, [n-1])
    receive do
      {:EXIT, pid, reason} ->
        :timer.sleep(500)
        IO.puts "Child process exits with reason #{reason}"
    end
  end
end
```

And here is the demo

![chain demo](/images/process_chain.gif)

The interesting fact is that after exit with **:chain\_breaks_here**, next exists are :normal. It is because the first process that catches :chain\_breaks_here exit code consumes it and then exits normally, so the error is swallowed by the first process that catches it. If we didn't trap exits in the chain and exit in the last process normally (:normal), the process would not exit at all - links prevent this. In other words: **When calling exit(:normal) the process will not finish, it will stay up**. Let's demo that as well!

Here is the code:
```elixir
defmodule LinksTestNoTrap do
  def chain 0 do
    IO.puts "normal exit in the last link"
    exit(:normal)
  end

  def chain n do
    IO.puts "create link in a chain no. #{n}"
    spawn_link(__MODULE__, :chain, [n-1])
    receive do
      msg -> IO.puts "#{n} received #{msg}"
    end
  end
end
```

And here is the demo

![chain demo](/images/process_chain_no_break.gif)


## Links are bidirectional

![oracle matrix meme](/images/3_musketeers_links.jpg)

So far we have been killing processes that are children of other processes. The question is:

> Q: If I kill the parent, do links break then?

> A: Yes, links are bidirectional

Let's create a tree of processes and kill the root of that tree:

```elixir
defmodule Bidirectional do
  def leaf name do
    receive do
      msg -> IO.puts "#{name} received #{msg}"
    end
  end

  def node name do
    spawn_link __MODULE__, :leaf, ["node: #{name} first leaf"]
    spawn_link __MODULE__, :leaf, ["node: #{name} second leaf"]
    spawn_link __MODULE__, :leaf, ["node: #{name} third leaf"]
    receive do
      msg -> IO.puts "#{name} received #{msg}"
    end
  end

  def kernel do
    spawn_link __MODULE__, :node, ["first node"]
    spawn_link __MODULE__, :node, ["second node"]
    receive do
      msg -> IO.puts "kernel received #{msg}"
    end
  end

  def create_graph do
    spawn_link __MODULE__, :kernel, []
  end
end
```

The code is fairly simple, create_graph function creates a kernel process, which spawns and link 2 node processes and each node creates 3 leafs. Then we kill the kernel PID and see what is going to happen. Hard to imagine? Let's visualize that!


![bidirectional links demo](/images/links_on_a_tree.gif)

Everything happens as planned and the entire tree is killed. Death of the kernel process causes a chain reaction and everything dies. Even our shell which is linked with the kernel dies as well!
