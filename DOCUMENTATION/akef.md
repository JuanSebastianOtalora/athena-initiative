<!--
  Athena Knowledge Exchange Format (AKEF) — v1.0
  Canonical copy: CANONICAL/ATHENA KNOWLEDGE EXCHANGE FORMAT.md
  This is a committed reference copy; treat CANONICAL/ as the source of truth.
-->

# Athena Knowledge Exchange Format (AKEF)

## Ontology & XML Schema Specification (v1.0)

---

# Purpose

The Athena Knowledge Exchange Format (AKEF) defines how knowledge is represented independently from any specific application, database, or interface.

AKEF is **not** a webpage format, a database schema, or a programming language. It is an ontology describing how knowledge, reasoning, decisions, documentation, and media are organized and related.

The same AKEF document should be consumable by:

* Desktop applications
* Web applications
* Mobile devices
* Mixed Reality devices
* Command Line Interfaces
* APIs
* Future interfaces not yet designed

Each interface is free to present the same knowledge differently while preserving the underlying structure.

---

# Design Philosophy

Athena separates **knowledge** from **presentation**.

Traditional software stores information inside pages.

Athena stores reusable knowledge artifacts connected through semantic relationships.

Interfaces simply visualize and interact with that graph.

This separation allows the same knowledge to exist independently from any particular technology or user interface.

---

# Core Principles

AKEF follows several architectural principles.

* Graph-first rather than page-first.
* Knowledge independent from presentation.
* Semantic relationships over directory structures.
* Reusable knowledge artifacts.
* Multiple presentations over one knowledge space.
* Human-readable.
* Machine-readable.
* Renderer independent.
* Extensible without breaking compatibility.
* Long-term maintainability.

---

# XML Fundamentals

AKEF is represented using XML.

XML provides three primary mechanisms.

## 1. Elements (Tags)

Elements represent objects.

Objects define concepts that have their own responsibilities and may contain additional information.

Example

```xml
<node>
```

Examples of Athena objects include

* Graph
* Node
* Artifact
* Relationship
* View
* Media
* Metadata

If something may contain children or additional properties, it should generally be represented as an element.

---

## 2. Attributes

Attributes describe an object.

They are small pieces of information that modify an element but do not become separate objects.

Example

```xml
<node
    id="athena://node/mission"
    node_type="topic">
```

Typical attributes include

* id
* node_type
* family
* class
* kind
* target
* role
* weight
* format
* language
* version

Rule of thumb:

If the information is a simple property, prefer an attribute.

---

## 3. Text Content

Text content contains the actual information.

Example

```xml
<title>
Mission
</title>
```

or

```xml
<payload format="markdown">
Athena preserves reasoning...
</payload>
```

Text should never define structure.

Structure belongs to elements.

---

# Ontology

AKEF is built around five primary objects.

---

# Graph

## Responsibility

A Graph represents a complete knowledge space.

It defines the scope of a collection of interconnected knowledge.

A graph contains

* Nodes
* Artifacts
* Relationships
* Views

Graphs enable

* import/export
* validation
* versioning
* distribution
* collaboration

A graph is the highest-level organizational object inside Athena.

---

# Node

## Responsibility

A Node represents a coordinate within the knowledge space.

Nodes organize information.

Nodes do **not** contain the knowledge itself.

Instead, they reference reusable artifacts.

## Attributes

| Attribute | Purpose                                                                 |
| --------- | ----------------------------------------------------------------------- |
| id        | Globally unique URI                                                     |
| node_type | Defines the structural role of the node (topic, collection, root, etc.) |

## Elements

```text
title
subtitle
artifact references
references
metadata
```

A Node answers

> Where does this topic exist within the knowledge graph?

---

# Artifact

## Responsibility

Artifacts contain the actual knowledge.

They represent reusable reasoning, documentation, decisions, media references, code, or any other knowledge asset.

Artifacts may be referenced by multiple nodes without duplication.

## Attributes

| Attribute | Purpose                      |
| --------- | ---------------------------- |
| id        | Globally unique URI          |
| family    | Highest taxonomy level       |
| class     | Middle taxonomy level        |
| kind      | Most specific taxonomy level |

## Elements

```text
payload
media
metadata
```

Example taxonomy

```text
Knowledge
    Graph
        Reasoning

Knowledge
    Graph
        Decision

Knowledge
    Document
        Manual

Knowledge
    Document
        Tutorial

Media
    Image
        Diagram

Media
    Video
        Walkthrough
```

Artifacts answer

> What knowledge exists?

---

# Relationship

## Responsibility

Relationships describe why two objects are connected.

Every connection inside Athena has semantic meaning.

Relationships may connect

* Node → Node
* Node → Artifact
* Artifact → Artifact

## Attributes

| Attribute     | Purpose                                                         |
| ------------- | --------------------------------------------------------------- |
| target        | Target URI                                                      |
| role          | Semantic meaning                                                |
| weight        | Relative importance for visualization, navigation and retrieval |
| bidirectional | Indicates whether traversal is reciprocal                       |

Example roles

```text
contains
extends
implements
supports
motivates
prerequisite
example_of
contrasts
contradicts
depends_on
related_to
```

Relationships answer

> Why are these objects connected?

---

# Media

## Responsibility

Media provides supporting visual or auditory information.

Media is never the knowledge itself.

It supports understanding.

## Attributes

Typical attributes

```text
type
kind
path
caption
credit
alt
```

Example taxonomy

```text
Media

Image
    Diagram

Image
    Hero

Video
    Walkthrough

Video
    Demonstration

Audio
    Narration
```

Media answers

> What additional resources help explain this knowledge?

---

# Metadata

## Responsibility

Metadata provides contextual information about an object.

Metadata does not define knowledge.

It describes it.

Metadata may be attached to

* Graphs
* Nodes
* Artifacts
* Relationships
* Media

Typical metadata

```text
version
status
author
difficulty
domain
keywords
license
created
updated
```

Metadata answers

> What should be known about this object?

---

# View

## Responsibility

Views define how a graph is entered and presented.

Views never modify knowledge.

They only describe a presentation over an existing graph.

A single graph may expose many views.

Examples

* Website
* Documentation
* Timeline
* CLI
* XR
* Search
* Tree

## Attributes

| Attribute    | Purpose                    |
| ------------ | -------------------------- |
| id           | Unique identifier          |
| root         | Root node URI              |
| presentation | Desired presentation style |

Views answer

> How should this portion of the graph be explored?

---

# Taxonomy

AKEF classifies knowledge using three hierarchical levels.

```text
Family
    ↓
Class
    ↓
Kind
```

Example

```text
Knowledge
    Graph
        Reasoning

Knowledge
    Graph
        Decision

Knowledge
    Document
        Manual

Media
    Image
        Diagram

Tool
    Software
        Desktop
```

This taxonomy enables semantic zooming while keeping every object consistently classified.

---

# URI Convention

Every object inside Athena should possess a globally unique URI.

Examples

```text
athena://graph/about

athena://node/knowledge/computer_assembly

athena://artifact/knowledge/reasoning/gpu_selection

athena://artifact/media/video/assembly_walkthrough
```

URIs ensure every object can be referenced without ambiguity.

---

# Separation of Responsibilities

| Object       | Responsibility                     |
| ------------ | ---------------------------------- |
| Graph        | Defines a knowledge space          |
| Node         | Defines where knowledge exists     |
| Artifact     | Contains the reusable knowledge    |
| Relationship | Explains why objects are connected |
| Media        | Supports understanding             |
| Metadata     | Describes an object                |
| View         | Defines how knowledge is presented |

---

# Traditional Knowledge vs Athena

| Traditional Systems       | Athena                                   |
| ------------------------- | ---------------------------------------- |
| Hierarchical folders      | Semantic graphs                          |
| Pages contain information | Nodes reference reusable artifacts       |
| Navigation through menus  | Traversal through semantic relationships |
| One interface             | Multiple presentations over one graph    |
| Static documentation      | Dynamic reusable knowledge               |
| Directory hierarchy       | Semantic collections and graph traversal |

---

# Guiding Rules

When extending AKEF, the following principles should always apply.

1. Structure and presentation remain independent.
2. Objects define responsibilities.
3. Attributes define simple properties.
4. Text contains knowledge, never structure.
5. Relationships always carry semantic meaning.
6. Knowledge should be reusable rather than duplicated.
7. Every object should have a globally unique identifier.
8. The ontology should remain renderer-independent.
9. New object types should extend the ontology without breaking previous versions.
10. Every design decision should prioritize long-term preservation, interoperability, and accessibility over implementation convenience.
